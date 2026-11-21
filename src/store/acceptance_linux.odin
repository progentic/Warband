package store

import a "../audit"
import e "../domain/events"
import client "../runtime/client"
import policy "../state"

@(private)
ACCEPTED_DDL :: `CREATE TABLE accepted_attempts (
  store_id BLOB NOT NULL CHECK(length(store_id)=16),
  epoch BLOB NOT NULL CHECK(length(epoch)=8),
  attempt_id BLOB NOT NULL CHECK(length(attempt_id)=16 AND attempt_id<>zeroblob(16)),
  transition_id BLOB NOT NULL CHECK(length(transition_id)=16 AND transition_id<>zeroblob(16)),
  sequence BLOB NOT NULL CHECK(length(sequence)=8),
  PRIMARY KEY(store_id,epoch,attempt_id),
  UNIQUE(store_id,epoch,transition_id),
  UNIQUE(store_id,epoch,sequence),
  FOREIGN KEY(store_id,epoch,sequence) REFERENCES events(store_id,epoch,sequence)
) STRICT, WITHOUT ROWID`

@(private)
AcceptedBinding :: struct {attempt: e.AttemptId, event: a.TransitionAccepted}
@(private)
AcceptanceCheck :: struct {using binding: AcceptedBinding, session: ^client.Session}

@(private)
insert_accepted :: proc(db: Database, attempt: e.AttemptId, event: a.TransitionAccepted) -> bool {
	attempt, event := attempt,event
	epoch,seq := word(u64(event.reference.epoch)),word(u64(event.reference.sequence))
	return change(db,"INSERT INTO accepted_attempts VALUES(?,?,?,?,?)",event.reference.store[:],epoch[:],attempt[:],event.transition[:],seq[:])
}

@(private)
index_schema :: proc(db: Database) -> bool {
	stmt, ok := bound(db,"SELECT sql FROM sqlite_schema WHERE tbl_name='accepted_attempts' AND sql IS NOT NULL")
	if !ok { return false }
	defer sqlite3_finalize(stmt)
	return sqlite3_step(stmt)==ROW && string(sqlite3_column_text(stmt,0))==ACCEPTED_DDL && sqlite3_step(stmt)==DONE
}

@(private)
index_matches :: proc(dbstate: ^WriterState, bindings: []AcceptedBinding) -> bool {
	if !index_schema(dbstate.db) || read_scalar(dbstate,"SELECT count(*) FROM accepted_attempts") != i64(len(bindings)) { return false }
	for b in bindings {
		b := b
		ref := b.event.reference
		epoch,seq := word(u64(ref.epoch)),word(u64(ref.sequence))
		stmt, ok := bound(dbstate.db,"SELECT transition_id,sequence FROM accepted_attempts WHERE store_id=? AND epoch=? AND attempt_id=?",
		                  ref.store[:],epoch[:],b.attempt[:])
		if !ok { return false }
		match := sqlite3_step(stmt)==ROW && string(column(stmt,0))==string(b.event.transition[:]) &&
		         string(column(stmt,1))==string(seq[:]) && sqlite3_step(stmt)==DONE
		if sqlite3_finalize(stmt)!=0 || !match { return false }
	}
	return true
}

// Runs only in the explicit maintenance command, inside the writer gate.
// Never synthesize a row from an unconfirmed SQLite suffix or repair a conflicting index.
provision_acceptance_index :: proc(w: VerifiedWriter, cp: e.Checkpoint, s: ^client.Session) -> bool {
	dbstate := cast(^WriterState)w
	if !change(dbstate.db,"BEGIN IMMEDIATE") { return false }
	committed := false
	defer if !committed { _ = change(dbstate.db,"ROLLBACK") }
	bindings: [dynamic]AcceptedBinding
	imports: [dynamic]Import
	defer delete(bindings)
	defer delete(imports)
	seg,ok := inspect_segment(dbstate,cp,nil,&imports,s,nil,&bindings)
	if !ok || seg.journal != cp || !mark_matches(dbstate,cp.store,seg.last_import) { return false }
	if read_scalar(dbstate,"SELECT count(*) FROM sqlite_schema WHERE name='accepted_attempts'") == i64(0) {
		if !change(dbstate.db,ACCEPTED_DDL) { return false }
		for b in bindings {
			if !insert_accepted(dbstate.db,b.attempt,b.event) { return false }
		}
	}
	committed = index_matches(dbstate,bindings[:]) && client.within_budget(s) && change(dbstate.db,"COMMIT")
	return committed
}

@(private)
acceptance_view :: proc(w: VerifiedWriter, cp: e.Checkpoint, s: ^client.Session) -> (NoopHistory,bool) {
	dbstate := cast(^WriterState)w
	h := NoopHistory{acceptance_scan=true}
	imports: [dynamic]Import
	bindings: [dynamic]AcceptedBinding
	defer delete(imports)
	defer delete(bindings)
	seg,ok := inspect_segment(dbstate,cp,nil,&imports,s,&h,&bindings)
	h.mark = seg.last_import
	return h,ok && seg.journal==cp && mark_matches(dbstate,cp.store,h.mark) && index_matches(dbstate,bindings[:])
}

acceptance_snapshot :: proc(w: VerifiedWriter, cp: e.Checkpoint, s: ^client.Session) -> (NoopHistory,bool) {
	db := (cast(^WriterState)w).db
	if !change(db,"BEGIN") { return {},false }
	defer change(db,"ROLLBACK")
	return acceptance_view(w,cp,s)
}

@(private)
eligible_in_transaction :: proc(w: VerifiedWriter, cp: e.Checkpoint, check: AcceptanceCheck) -> bool {
	h,ok := acceptance_view(w,cp,check.session)
	v := check.event
	if !ok || policy.decide(h.evidence,v.evaluation,v.expected_task_version,v.expected_control_revision) != .Eligible { return false }
	claim := h.claim.(a.DispatchClaimed)
	return claim.reference==v.claim && claim.attempt==check.attempt
}

append_acceptance :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,v: a.TransitionAccepted) -> bool {
	h,verified := acceptance_snapshot(w,cp,s)
	if !verified || policy.decide(h.evidence,v.evaluation,v.expected_task_version,v.expected_control_revision) != .Eligible ||
	   cp.sequence==max(e.Sequence) || v.reference!=(e.EventRef{cp.store,cp.epoch,cp.sequence+1}) || v.previous_head!=cp.head { return false }
	claim := h.claim.(a.DispatchClaimed)
	if claim.reference!=v.claim { return false }
	wire,err := a.encode_transition_accepted(v,cp.store,cp.epoch)
	digest,de := a.digest_transition_accepted(v,cp.store,cp.epoch)
	if err!=.None || de!=.None { return false }
	check := AcceptanceCheck{{claim.attempt,v},s}
	_,ok := append_pledged(w,s,cp,h.mark,nil,wire[:],digest,client.wb_elapsed_ms(),s.deadline,&check)
	return ok
}
