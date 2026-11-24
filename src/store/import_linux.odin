package store

import e "../domain/events"
import a "../audit"
import state "../state"
import c "../custody"
import client "../runtime/client"
import "core:encoding/endian"
import "core:crypto/sha2"
import "core:fmt"
import "base:runtime"
import "core:sys/linux"

foreign import sqlite_import "warband_sqlite:libsqlite3.a"
@(private)
foreign sqlite_import {
	sqlite3_bind_blob :: proc(stmt: Statement, index: i32, data: rawptr, size: i32, destructor: rawptr) -> i32 ---
	sqlite3_column_blob :: proc(stmt: Statement, column: i32) -> rawptr ---
	sqlite3_column_bytes :: proc(stmt: Statement, column: i32) -> i32 ---
	sqlite3_hard_heap_limit64 :: proc(limit: i64) -> i64 ---
}

ReceiptId :: struct {ordinal: u64, hash: [32]u8}
Import :: struct {id: ReceiptId, digest: [32]u8, ref: e.EventRef}
Row :: struct {
	pledge: e.Pledge,
	receipt: Maybe(Import),
	acceptance: Maybe(a.TransitionAccepted),
	marker_acceptance: Maybe(a.MarkerAccepted),
	attempt: e.AttemptId,
	marker_claim: Maybe(a.MarkerClaim),
	observation: Maybe(a.ObservationRecorded),
	evaluation: Maybe(a.EvaluationRecorded),
	marker_observation: Maybe(a.MarkerObservation),
	marker_evaluation: Maybe(a.MarkerEvaluation),
}
Segment :: struct {journal: e.Checkpoint, tail: Maybe(e.Pledge), tail_import: Maybe(Import), last_import: u64}

@(private)
word :: proc(v: u64) -> [8]u8 {
	b: [8]u8
	endian.put_u64(b[:],.Little,v)
	return b
}

@(private)
bound :: proc(db: Database, sql: cstring, args: ..[]u8) -> (Statement, bool) {
	stmt: Statement
	if sqlite3_prepare_v2(db,sql,-1,&stmt,nil) != 0 { return nil,false }
	for arg,i in args {
		if sqlite3_bind_blob(stmt,i32(i+1),raw_data(arg),i32(len(arg)),rawptr(max(uintptr))) != 0 {
			sqlite3_finalize(stmt)
			return nil,false
		}
	}
	return stmt,true
}

@(private)
column :: proc(stmt: Statement, index: i32) -> []u8 {
	if sqlite3_column_type(stmt,index) != 4 { return nil }
	n := sqlite3_column_bytes(stmt,index)
	data := cast([^]u8)sqlite3_column_blob(stmt,index)
	if data == nil { return nil }
	return data[:n]
}

@(private)
change :: proc(db: Database, sql: cstring, args: ..[]u8) -> bool {
	return transaction_change(db,false,"",sql,..args)
}

SQLITE_FAULT :: #config(WARBAND_TEST_SQLITE_FAULT, 0) // 1 calibrate, 2 page cap, 3 veto
@(private)
transaction_change :: proc(db: Database, receipt: bool, label: string, sql: cstring, args: ..[]u8) -> bool {
	stmt, ok := bound(db,sql,..args)
	if !ok { return false }
	rc := sqlite3_step(stmt)
	when SQLITE_FAULT != 0 {
		if receipt { fmt.eprintln("step",label,rc & 255,sqlite3_extended_errcode(db)) }
	}
	final := sqlite3_finalize(stmt)
	when SQLITE_FAULT == 1 {
		if receipt && rc == DONE && final == 0 {
			state := WriterState{db=db}
			pages, valid := read_scalar(&state,"PRAGMA main.page_count").(i64)
			if !valid { return false }
			fmt.eprintln("pages",label,pages)
		}
	}
	return final == 0 && rc == DONE
}

@(private)
event_row :: proc(db: Database, ref: e.EventRef, history: ^NoopHistory = nil, marker := false, requests := false) -> (Row, bool) {
	ref := ref
	epoch, sequence := word(u64(ref.epoch)), word(u64(ref.sequence))
	query :: "SELECT canonical_event,custody_ordinal,record_hash FROM events LEFT JOIN denial_imports USING(store_id,epoch,sequence) WHERE store_id=? AND epoch=? AND sequence=?"
	stmt, ok := bound(db,query,ref.store[:],epoch[:],sequence[:])
	if !ok { return {},false }
	defer sqlite3_finalize(stmt)
	if sqlite3_step(stmt) != ROW { return {},false }
	b := column(stmt,0)
	if len(b) < 88 || len(b) > 65536+88 { return {},false }
	kind, _ := endian.get_u16(b[6:8],.Little)
	imported := false
	accepted: Maybe(a.TransitionAccepted)
	marker_accepted: Maybe(a.MarkerAccepted)
	attempt: e.AttemptId
	marker_claim: Maybe(a.MarkerClaim)
	observation: Maybe(a.ObservationRecorded)
	evaluation: Maybe(a.EvaluationRecorded)
	marker_observation: Maybe(a.MarkerObservation)
	marker_evaluation: Maybe(a.MarkerEvaluation)
	if history != nil && !history.acceptance_scan && kind != 1 && kind != 2 && kind != 3 && kind != 4 && kind != 5 && kind != 6 && kind != 8 { return {},false }
	switch kind {
	case 1:
		v, decode_err := a.decode_task_created(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			if history.task != nil { return {},false }
			history.task = v
			history.task_version = 1
		}
	case 2:
		v, decode_err := a.decode_proposal_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			if history.proposal != nil { return {},false }
			history.proposal = v
		}
	case 3:
		v, decode_err := a.decode_authorization_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			if history.permit != nil { return {},false }
			history.permit = v
			if v.decision == .Permit { history.control_revision += 1 }
		}
	case 4:
		v, decode_err := a.decode_dispatch_claimed(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		attempt = v.attempt
		if history != nil {
			if history.claim != nil { return {},false }
			history.claim = v
			history.control_revision += 1
		}
	case 5:
		v, decode_err := a.decode_observation_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		observation = v
		if history != nil {
			claim, found := history.claim.(a.DispatchClaimed)
			if !found || v.claim != claim.reference || history.observation != nil || !available_evidence(history^,v.evidence) { return {},false }
			history.observation = v
			copy(history.observation_bytes[:],b)
		}
	case 6:
		v, decode_err := a.decode_evaluation_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		evaluation = v
		if history != nil {
			obs, found := history.observation.(a.ObservationRecorded)
			if !found || v.observation != obs.reference || v.claim != obs.claim ||
			   v.observed_event_digest != history.observation_digest || history.evaluation != nil || !available_evidence(history^,v.evidence) { return {},false }
			history.evaluation = v
		}
	case 7:
		v, decode_err := a.decode_transition_accepted(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		accepted = v
		if history != nil {
			if history.transition != nil || state.decide(history.evidence,v.evaluation,v.expected_task_version,v.expected_control_revision) != .Eligible { return {},false }
			claim := history.claim.(a.DispatchClaimed)
			if v.claim != claim.reference { return {},false }
			history.transition = v
			history.task_version += 1
			history.control_revision += 1
		}
	case 8:
		v, decode_err := a.decode_rejection_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		imported = v.producer == 5 && v.stage == 7 && v.reason == 13 && v.related == nil
	case 9:
		v, decode_err := a.decode_capability_revoked(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			permit, found := history.permit.(a.AuthorizationRecorded)
			if !found || v.authorization != permit.reference || v.capability != permit.capability ||
			   history.revoked || v.expected_control_revision != history.control_revision { return {},false }
			history.revoked = true
			history.control_revision += 1
		}
	case 10:
		v, decode_err := a.decode_attempt_disposition(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			claim, found := history.claim.(a.DispatchClaimed)
			if !found || v.claim != claim.reference || history.terminal || history.transition != nil ||
			   v.expected_control_revision != history.control_revision { return {},false }
			history.terminal = true
			history.control_revision += 1
		}
	case 11:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_proposal(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
	case 12:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_approval(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
	case 13:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_permit(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
	case 14:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_claim(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
		marker_claim=v
	case 15:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_observation(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
		marker_observation=v
	case 16:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_evaluation(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
		marker_evaluation=v
	case 17:
		if !marker || history!=nil { return {},false }
		v,err := a.decode_marker_accepted(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
		marker_accepted=v
	case 18:
		if !requests || history!=nil { return {},false }
		v,err := a.decode_request_issued(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
	case 19:
		if !requests || history!=nil { return {},false }
		v,err := a.decode_request_expired(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return {},false }
	case: return {},false
	}
	// Hash the persisted body itself after the kind decoder has validated its representation.
	hash: sha2.Context_256
	sha2.init_256(&hash)
	domain: string = a.EventDomain
	sha2.update(&hash, transmute([]u8)domain)
	sha2.update(&hash,b[:len(b)-32])
	digest: [32]u8
	sha2.final(&hash,digest[:])
	if history != nil && kind == 5 { history.observation_digest = digest }
	p := e.Pledge{store=ref.store,epoch=ref.epoch,sequence=ref.sequence,previous_sequence=ref.sequence-1,digest=digest}
	copy(p.previous_head[:],b[len(b)-32:])
	p.head = c.derive_head(p)
	row := Row{pledge=p,acceptance=accepted,marker_acceptance=marker_accepted,attempt=attempt,marker_claim=marker_claim,
	           observation=observation,evaluation=evaluation,marker_observation=marker_observation,marker_evaluation=marker_evaluation}
	if imported {
		ord, hash := column(stmt,1), column(stmt,2)
		if len(ord)!=8 || len(hash)!=32 { return {},false }
		entry := Import{ref=ref}
		entry.id.ordinal,_ = endian.get_u64(ord,.Little)
		copy(entry.id.hash[:],hash)
		copy(entry.digest[:],b[len(b)-64:len(b)-32])
		row.receipt = entry
	} else if sqlite3_column_type(stmt,1) != 5 || sqlite3_column_type(stmt,2) != 5 { return {},false }
	return row,sqlite3_step(stmt)==DONE
}

@(private)
mark_matches :: proc(state: ^WriterState, id: e.StoreId, expected: u64) -> bool {
	id := id
	stmt, ok := bound(state.db,"SELECT store_id,last_imported_ordinal FROM import_watermarks")
	if !ok { return false }
	defer sqlite3_finalize(stmt)
	step := sqlite3_step(stmt)
	if expected == 0 { return step == DONE }
	b := word(expected)
	return step == ROW && string(column(stmt,0)) == string(id[:]) &&
	       string(column(stmt,1)) == string(b[:]) && sqlite3_step(stmt) == DONE
}

// Check every row in the installed epoch segment, including the checkpoint-covered prefix.
// Numbered primary-key lookups preserve numeric order with little-endian BLOB keys.
@(private)
inspect_segment :: proc(state: ^WriterState, cp: e.Checkpoint, genesis: Maybe([32]u8), imports: ^[dynamic]Import, s: ^client.Session, history: ^NoopHistory = nil, bindings: ^[dynamic]AcceptedBinding = nil, marker := false, requests := false) -> (Segment,bool) {
	total, ok := read_scalar(state,"SELECT count(*) FROM events").(i64)
	if !ok || total < 0 || !client.within_budget(s,u64(total)) { return {},false }
	result := Segment{journal={store=cp.store,epoch=cp.epoch}}
	if h, supplied := genesis.([32]u8); supplied { result.journal.head = h
	} else if cp.sequence == 0 { result.journal.head = cp.head }
	start_count := len(imports)
	for n in 1..=total {
		row, found := event_row(state.db,{cp.store,cp.epoch,e.Sequence(n)},history,marker,requests)
		if !found || !client.within_budget(s) { return {},false }
		p := row.pledge
		if n == 1 && genesis == nil && cp.sequence != 0 { result.journal.head = p.previous_head }
		if p.previous_head != result.journal.head { return {},false }
		if cp.sequence == 0 && n == 1 && p.previous_head != cp.head { return {},false }
		result.journal = {cp.store,cp.epoch,p.sequence,p.head}
		if p.sequence == cp.sequence && result.journal != cp { return {},false }
		if p.sequence > cp.sequence {
			result.tail = p
			result.tail_import = row.receipt
		}
		if accepted, present := row.acceptance.(a.TransitionAccepted); present && bindings != nil {
			if !client.within_budget(s,3) { return {},false }
			parent, resolved := event_row(state.db,accepted.claim)
			if !resolved || parent.attempt == (e.AttemptId{}) { return {},false }
			eval_row, read_eval := event_row(state.db,accepted.evaluation)
			ev, evaluated := eval_row.evaluation.(a.EvaluationRecorded)
			if !read_eval || !evaluated || ev.claim != accepted.claim || ev.verdict != .Verified { return {},false }
			obs_row, read_obs := event_row(state.db,ev.observation)
			obs, observed := obs_row.observation.(a.ObservationRecorded)
			if !read_obs || !observed || obs.claim != accepted.claim || obs.outcome != .Returned ||
			   obs_row.pledge.digest != ev.observed_event_digest { return {},false }
			if _, err := append(bindings,AcceptedBinding{parent.attempt,accepted.transition,accepted.reference}); err != nil { return {},false }
		}
		if accepted, present := row.marker_acceptance.(a.MarkerAccepted); present && bindings != nil {
			if !client.within_budget(s,3) { return {},false }
			claim_row,read_claim := event_row(state.db,accepted.claim,marker=true)
			claim,claimed := claim_row.marker_claim.(a.MarkerClaim)
			eval_row,read_eval := event_row(state.db,accepted.evaluation,marker=true)
			evaluation,evaluated := eval_row.marker_evaluation.(a.MarkerEvaluation)
			obs_row,read_obs := event_row(state.db,evaluation.observation,marker=true)
			observation,observed := obs_row.marker_observation.(a.MarkerObservation)
			if !read_claim || !claimed || !read_eval || !evaluated || !read_obs || !observed ||
			   claim.reference!=accepted.claim || evaluation.claim!=accepted.claim || evaluation.verdict!=.Verified ||
			   observation.reference!=evaluation.observation || observation.claim!=accepted.claim ||
			   obs_row.pledge.digest!=evaluation.observation_digest { return {},false }
			if _,err := append(bindings,AcceptedBinding{claim.attempt,accepted.transition,accepted.reference}); err!=nil { return {},false }
		}
		if entry, present := row.receipt.(Import); present {
			if entry.id.ordinal == 0 || (len(imports)>0 && entry.id.ordinal <= imports^[len(imports)-1].id.ordinal) { return {},false }
			if _, err := append(imports,entry); err != nil { return {},false }
			result.last_import = entry.id.ordinal
		}
	}
	if total == 0 && cp.sequence == 0 && result.journal != cp { return {},false }
	count, counted := read_scalar(state,"SELECT count(*) FROM denial_imports").(i64)
	return result,counted && count == i64(len(imports)-start_count)
}

limit_writer_cache :: proc(w: VerifiedWriter) -> bool {
	return configure_cache(cast(^WriterState)w)
}

inspect_writer :: proc(w: VerifiedWriter, cp: e.Checkpoint, genesis: Maybe([32]u8), imports: ^[dynamic]Import, session: ^client.Session, marker := false, requests := false) -> (Segment,bool) {
	return inspect_segment(cast(^WriterState)w,cp,genesis,imports,session,marker=marker,requests=requests)
}

watermark_matches :: proc(w: VerifiedWriter, id: e.StoreId, ordinal: u64) -> bool {
	return mark_matches(cast(^WriterState)w,id,ordinal)
}

// Archives stay under operator control with all SQLite/WAL files preserved.
inspect_archive :: proc(path: cstring, cp: e.Checkpoint, genesis: Maybe([32]u8), imports: ^[dynamic]Import, s: ^client.Session) -> bool {
	db: Database
	rc := sqlite3_open_v2(path,&db,1,nil)
	defer if db != nil { sqlite3_close(db) }
	if rc != 0 || sqlite3_db_readonly(db,"main") != 1 { return false }
	state := WriterState{db=db}
	if !configure_cache(&state) || !change(db,"BEGIN") || read_scalar(&state,"PRAGMA user_version") != i64(1) { return false }
	seg, ok := inspect_segment(&state,cp,genesis,imports,s)
	return ok && seg.journal == cp && mark_matches(&state,cp.store,seg.last_import)
}

@(private)
configure_cache :: proc(state: ^WriterState) -> bool {
	return set_connection_option(state,"PRAGMA cache_size=-8192") &&
	       read_scalar(state,"PRAGMA cache_size") == i64(-8192)
}

limit_sqlite :: proc() -> bool {
	if !library_matches_pin() { return false }
	_ = sqlite3_hard_heap_limit64(64*1024*1024)
	n := sqlite3_hard_heap_limit64(-1)
	return n > 0 && n <= 64*1024*1024
}

@(private)
proof_transaction :: proc(bytes: []u8, receipt: Maybe(Import), acceptance: ^AcceptanceCheck) -> bool {
	kind :: #config(WARBAND_TEST_TRANSACTION_KIND, 0)
	when kind == 5 {
		return receipt == nil && acceptance == nil && len(bytes) >= 8 && bytes[6] == 5 && bytes[7] == 0
	} else when kind == 7 {
		return acceptance != nil
	} else {
		#assert(kind == 0)
		return receipt != nil
	}
}

// Only the WAL proof binary registers this callback, immediately before COMMIT.
@(private)
stop_in_wal_commit :: proc "c" (_: rawptr, _: Database, _: cstring, frames: i32) -> i32 {
	context = runtime.default_context()
	fmt.eprintln("wal_frames", frames)
	if linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return 1 }
	return 0
}

@(private)
veto_receipt_commit :: proc "c" (_: rawptr) -> i32 {
	context = runtime.default_context()
	fmt.eprintln("commit_veto")
	return 1
}

@(private)
commit_event :: proc(w: VerifiedWriter, cp: e.Checkpoint, prior: u64, receipt: Maybe(Import), bytes: []u8, acceptance: ^AcceptanceCheck = nil, marker := false, request: ^RequestAppend = nil) -> bool {
	state := cast(^WriterState)w
	cp := cp
	db := state.db
	when SQLITE_FAULT == 2 {
		if receipt != nil {
			pages, ok := read_scalar(state,"PRAGMA main.page_count").(i64)
			if !ok || pages <= 0 { return false }
			limit := fmt.caprintf("PRAGMA main.max_page_count=%d",pages)
			defer delete(limit)
			if read_scalar(state,limit) != pages || read_scalar(state,"PRAGMA main.max_page_count") != pages { return false }
			fmt.eprintln("cap",pages)
		}
	}
	if !change(db,"BEGIN IMMEDIATE") { return false }
	committed := false
	defer if !committed { _ = change(db,"ROLLBACK") }
	count := read_scalar(state,"SELECT count(*) FROM events")
	if count != i64(cp.sequence) || !mark_matches(state,cp.store,prior) { return false }
	if cp.sequence > 0 {
		last, ok := event_row(db,{cp.store,cp.epoch,cp.sequence},marker=marker,requests=request!=nil)
		if !ok || last.pledge.head != cp.head { return false }
	}
	if request!=nil && !request_inventory(w,request.before) { return false }
	if acceptance != nil && !eligible_in_transaction(w,cp,acceptance^) { return false }
	epoch, seq := word(u64(cp.epoch)), word(u64(cp.sequence)+1)
	if !transaction_change(db,receipt!=nil,"event","INSERT INTO events(store_id,epoch,sequence,canonical_event) VALUES(?,?,?,?)",cp.store[:],epoch[:],seq[:],bytes) { return false }
	when #config(WARBAND_TEST_STOP_AFTER_EVENT_INSERT, false) {
		if proof_transaction(bytes,receipt,acceptance) && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return false }
	}
	if entry, present := receipt.(Import); present {
		ord := word(entry.id.ordinal)
		if !transaction_change(db,receipt!=nil,"binding","INSERT INTO denial_imports(store_id,custody_ordinal,record_hash,epoch,sequence) VALUES(?,?,?,?,?)",cp.store[:],ord[:],entry.id.hash[:],epoch[:],seq[:]) ||
		   !transaction_change(db,receipt!=nil,"watermark","INSERT INTO import_watermarks(store_id,last_imported_ordinal) VALUES(?,?) ON CONFLICT(store_id) DO UPDATE SET last_imported_ordinal=excluded.last_imported_ordinal",cp.store[:],ord[:]) { return false }
	}
	if request!=nil && !request_fact(db,bytes,true) { return false }
	if acceptance != nil && !insert_accepted(db,acceptance.binding) { return false }
	when #config(WARBAND_TEST_STOP_IN_WAL_COMMIT, false) {
		if proof_transaction(bytes,receipt,acceptance) {
			threshold, ok := read_scalar(state,"PRAGMA wal_autocheckpoint").(i64)
			if !ok || threshold <= 0 { return false }
			fmt.eprintln("wal_threshold", threshold)
			_ = sqlite3_wal_hook(db,stop_in_wal_commit,nil)
		}
	}
	when SQLITE_FAULT == 3 {
		if receipt != nil { _ = sqlite3_commit_hook(db,veto_receipt_commit,nil) }
	}
	committed = transaction_change(db,receipt!=nil,"commit","COMMIT")
	return committed
}

// This increment admits exactly one task/proposal. Any additional state-changing kind
// or duplicate binding withholds dispatch. Audit-only records may share the prefix.
NoopHistory :: struct {
	using evidence: state.Evidence,
	acceptance_scan: bool,
	mark: u64,
}

available_evidence :: proc(h: NoopHistory,id: e.EvidenceId) -> bool {
	task, created := h.task.(a.TaskCreated)
	auth, permitted := h.permit.(a.AuthorizationRecorded)
	obs, observed := h.observation.(a.ObservationRecorded)
	return id != (e.EvidenceId{}) && created && permitted && id != task.evidence && id != auth.evidence &&
	       (!observed || id != obs.evidence)
}

noop_history :: proc(w: VerifiedWriter, cp: e.Checkpoint, session: ^client.Session) -> (NoopHistory,bool) {
	state := cast(^WriterState)w
	if !change(state.db,"BEGIN") { return {},false }
	defer change(state.db,"ROLLBACK") // end this read snapshot
	imports: [dynamic]Import
	defer delete(imports)
	history: NoopHistory
	segment, ok := inspect_segment(state,cp,nil,&imports,session,&history)
	history.mark = segment.last_import
	return history,ok && segment.journal == cp && mark_matches(state,cp.store,history.mark)
}
