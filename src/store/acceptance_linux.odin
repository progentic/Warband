package store

import a "../audit"
import e "../domain/events"
import r "../replay"
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
AcceptedBinding :: struct {attempt: e.AttemptId, transition: e.TransitionId, reference: e.EventRef}
@(private)
AcceptanceCheck :: struct {
	using binding: AcceptedBinding,
	session: ^client.Session,
	marker: bool,
	root: e.Checkpoint,
	receipts: []r.Receipt,
	noop: a.TransitionAccepted,
	marker_event: a.MarkerAccepted,
}
MarkerAcceptanceIssue :: enum {None, Unavailable, HistorySegmentInvalid, HistoryRowsInvalid,
                               HistoryReceiptCountInvalid, HistoryReceiptBindingInvalid, HistoryProjectionInvalid, IndexInvalid,
                               VerdictInvalid, VersionsInvalid, ReferenceInvalid, CommitUnconfirmed}

@(private)
insert_accepted :: proc(db: Database, binding: AcceptedBinding) -> bool {
	binding := binding
	epoch,seq := word(u64(binding.reference.epoch)),word(u64(binding.reference.sequence))
	return change(db,"INSERT INTO accepted_attempts VALUES(?,?,?,?,?)",binding.reference.store[:],epoch[:],binding.attempt[:],binding.transition[:],seq[:])
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
		ref := b.reference
		epoch,seq := word(u64(ref.epoch)),word(u64(ref.sequence))
		stmt, ok := bound(dbstate.db,"SELECT transition_id,sequence FROM accepted_attempts WHERE store_id=? AND epoch=? AND attempt_id=?",
		                  ref.store[:],epoch[:],b.attempt[:])
		if !ok { return false }
		match := sqlite3_step(stmt)==ROW && string(column(stmt,0))==string(b.transition[:]) &&
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
			if !insert_accepted(dbstate.db,b) { return false }
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
	if check.marker { return marker_eligible_in_transaction(w,cp,check) }
	h,ok := acceptance_view(w,cp,check.session)
	v := check.noop
	if !ok || policy.decide(h.evidence,v.evaluation,v.expected_task_version,v.expected_control_revision) != .Eligible { return false }
	claim := h.claim.(a.DispatchClaimed)
	return claim.reference==v.claim && claim.attempt==check.attempt
}

@(private)
marker_rows :: proc(state: ^WriterState,cp: e.Checkpoint,s: ^client.Session) -> ([]r.Row,bool) {
	count,ok := read_scalar(state,"SELECT count(*) FROM events").(i64)
	if !ok || count!=i64(cp.sequence) || !client.within_budget(s,2*u64(count)) { return nil,false }
	rows,err := make([]r.Row,int(count),context.allocator)
	if err!=nil { return nil,false }
	epoch := word(u64(cp.epoch))
	store_id := cp.store
	for &row,i in rows {
		seq := word(u64(i+1))
		stmt,prepared := bound(state.db,"SELECT canonical_event FROM events WHERE store_id=? AND epoch=? AND sequence=?",store_id[:],epoch[:],seq[:])
		if !prepared { return nil,false }
		if sqlite3_step(stmt)!=ROW || !client.within_budget(s) { sqlite3_finalize(stmt); return nil,false }
		bytes := column(stmt,0)
		if len(bytes)<88 || len(bytes)>65536+88 { sqlite3_finalize(stmt); return nil,false }
		data,allocated := make([]u8,len(bytes),context.allocator)
		if allocated!=nil { sqlite3_finalize(stmt); return nil,false }
		copy(data,bytes)
		row={{cp.store,cp.epoch,e.Sequence(i+1)},data}
		if sqlite3_finalize(stmt)!=0 { return nil,false }
	}
	return rows,true
}

@(private)
marker_acceptance_view :: proc(w: VerifiedWriter,cp,root: e.Checkpoint,receipts: []r.Receipt,s: ^client.Session) -> (r.Result,u64,MarkerAcceptanceIssue) {
	state := cast(^WriterState)w
	imports: [dynamic]Import
	bindings: [dynamic]AcceptedBinding
	defer delete(imports)
	defer delete(bindings)
	seg,valid := inspect_segment(state,cp,root.head,&imports,s,nil,&bindings,marker=true)
	if !valid || seg.journal!=cp || !mark_matches(state,cp.store,seg.last_import) { return {},0,.HistorySegmentInvalid }
	if !index_matches(state,bindings[:]) { return {},0,.IndexInvalid }
	if len(imports)!=len(receipts) { return {},0,.HistoryReceiptCountInvalid }
	for entry,i in imports {
		if receipts[i].digest!=entry.digest { return {},0,.HistoryReceiptBindingInvalid }
	}
	rows,read := marker_rows(state,cp,s)
	if !read { return {},0,.HistoryRowsInvalid }
	segments := [?]r.Segment{{rows=rows}}
	view := r.project_markers(root,cp,nil,segments[:],receipts)
	if view.error!=.None || view.readiness!=.Ready || view.receipts_used!=len(receipts) || len(view.tasks)!=1 || !view.tasks[0].marker {
		return view,seg.last_import,.HistoryProjectionInvalid
	}
	return view,seg.last_import,.None
}

@(private)
marker_acceptance_preflight :: proc(w: VerifiedWriter,view: r.Result,check: AcceptanceCheck) -> MarkerAcceptanceIssue {
	p := view.tasks[0]
	v := check.marker_event
	row,found := event_row((cast(^WriterState)w).db,v.evaluation,marker=true)
	evaluation,evaluated := row.marker_evaluation.(a.MarkerEvaluation)
	if !found || !evaluated || evaluation.reference!=v.evaluation || evaluation.claim!=v.claim || p.attempt!=check.attempt { return .ReferenceInvalid }
	if evaluation.verdict!=.Verified || p.verdict!=u8(a.MarkerVerdict.Verified) || !p.consumed || p.complete || p.revoked || p.disposition!=0 { return .VerdictInvalid }
	if p.task_version!=v.expected_task_version || p.control_revision!=v.expected_control_revision { return .VersionsInvalid }
	return .None
}

@(private)
marker_eligible_in_transaction :: proc(w: VerifiedWriter,cp: e.Checkpoint,check: AcceptanceCheck) -> bool {
	view,_,issue := marker_acceptance_view(w,cp,check.root,check.receipts,check.session)
	return issue==.None && marker_acceptance_preflight(w,view,check)==.None
}

@(private)
marker_index_snapshot :: proc(w: VerifiedWriter,cp: e.Checkpoint,s: ^client.Session) -> bool {
	db := (cast(^WriterState)w).db
	if !change(db,"BEGIN") { return false }
	defer change(db,"ROLLBACK")
	imports: [dynamic]Import
	bindings: [dynamic]AcceptedBinding
	defer delete(imports)
	defer delete(bindings)
	seg,ok := inspect_segment(cast(^WriterState)w,cp,nil,&imports,s,nil,&bindings,marker=true)
	return ok && seg.journal==cp && mark_matches(cast(^WriterState)w,cp.store,seg.last_import) && index_matches(cast(^WriterState)w,bindings[:])
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
	check := AcceptanceCheck{binding={claim.attempt,v.transition,v.reference},session=s,noop=v}
	_,ok := append_pledged(w,s,cp,h.mark,nil,wire[:],digest,client.wb_elapsed_ms(),s.deadline,&check)
	return ok
}

append_marker_acceptance :: proc(w: VerifiedWriter,s: ^client.Session,root,cp: e.Checkpoint,receipts: []r.Receipt,v: a.MarkerAccepted) -> MarkerAcceptanceIssue {
	db := (cast(^WriterState)w).db
	if !change(db,"BEGIN") { return .Unavailable }
	view,mark,issue := marker_acceptance_view(w,cp,root,receipts,s)
	_ = change(db,"ROLLBACK")
	if issue!=.None { return issue }
	if cp.sequence==max(e.Sequence) || v.reference!=(e.EventRef{cp.store,cp.epoch,cp.sequence+1}) || v.previous_head!=cp.head { return .ReferenceInvalid }
	p := view.tasks[0]
	check := AcceptanceCheck{binding={p.attempt,v.transition,v.reference},session=s,marker=true,root=root,receipts=receipts,marker_event=v}
	if issue=marker_acceptance_preflight(w,view,check); issue!=.None { return issue }
	wire,err := a.encode_marker_accepted(v,cp.store,cp.epoch)
	digest,de := a.digest_marker_accepted(v,cp.store,cp.epoch)
	if err!=.None || de!=.None { return .ReferenceInvalid }
	_,ok := append_pledged(w,s,cp,mark,nil,wire[:],digest,client.wb_elapsed_ms(),s.deadline,&check,marker=true)
	return .None if ok else .CommitUnconfirmed
}
