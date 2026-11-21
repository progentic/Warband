package store

import e "../domain/events"
import a "../audit"
import c "../custody"
import client "../runtime/client"
import "core:encoding/endian"
import "core:crypto/sha2"

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
Row :: struct {pledge: e.Pledge, receipt: Maybe(Import)}
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
	stmt, ok := bound(db,sql,..args)
	if !ok { return false }
	done := sqlite3_step(stmt) == DONE
	return sqlite3_finalize(stmt) == 0 && done
}

@(private)
event_row :: proc(db: Database, ref: e.EventRef, history: ^NoopHistory = nil) -> (Row, bool) {
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
	if history != nil && kind != 1 && kind != 2 && kind != 3 && kind != 4 && kind != 8 { return {},false }
	switch kind {
	case 1:
		v, decode_err := a.decode_task_created(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			if history.task != nil { return {},false }
			history.task = v
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
		}
	case 4:
		v, decode_err := a.decode_dispatch_claimed(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		if history != nil {
			if history.claim != nil { return {},false }
			history.claim = v
		}
	case 5:
		v, decode_err := a.decode_observation_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
	case 6:
		v, decode_err := a.decode_evaluation_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
	case 7:
		v, decode_err := a.decode_transition_accepted(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
	case 8:
		v, decode_err := a.decode_rejection_recorded(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
		imported = v.producer == 5 && v.stage == 7 && v.reason == 13 && v.related == nil
	case 9:
		v, decode_err := a.decode_capability_revoked(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
	case 10:
		v, decode_err := a.decode_attempt_disposition(b,ref.store,ref.epoch)
		if decode_err != .None || v.reference != ref { return {},false }
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
	p := e.Pledge{store=ref.store,epoch=ref.epoch,sequence=ref.sequence,previous_sequence=ref.sequence-1,digest=digest}
	copy(p.previous_head[:],b[len(b)-32:])
	p.head = c.derive_head(p)
	row := Row{pledge=p}
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
inspect_segment :: proc(state: ^WriterState, cp: e.Checkpoint, genesis: Maybe([32]u8), imports: ^[dynamic]Import, s: ^client.Session, history: ^NoopHistory = nil) -> (Segment,bool) {
	total, ok := read_scalar(state,"SELECT count(*) FROM events").(i64)
	if !ok || total < 0 || !client.within_budget(s,u64(total)) { return {},false }
	result := Segment{journal={store=cp.store,epoch=cp.epoch}}
	if h, supplied := genesis.([32]u8); supplied { result.journal.head = h
	} else if cp.sequence == 0 { result.journal.head = cp.head }
	start_count := len(imports)
	for n in 1..=total {
		row, found := event_row(state.db,{cp.store,cp.epoch,e.Sequence(n)},history)
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

inspect_writer :: proc(w: VerifiedWriter, cp: e.Checkpoint, genesis: Maybe([32]u8), imports: ^[dynamic]Import, session: ^client.Session) -> (Segment,bool) {
	return inspect_segment(cast(^WriterState)w,cp,genesis,imports,session)
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
commit_event :: proc(w: VerifiedWriter, cp: e.Checkpoint, prior: u64, receipt: Maybe(Import), bytes: []u8) -> bool {
	state := cast(^WriterState)w
	cp := cp
	db := state.db
	if !change(db,"BEGIN IMMEDIATE") { return false }
	committed := false
	defer if !committed { _ = change(db,"ROLLBACK") }
	count := read_scalar(state,"SELECT count(*) FROM events")
	if count != i64(cp.sequence) || !mark_matches(state,cp.store,prior) { return false }
	if cp.sequence > 0 {
		last, ok := event_row(db,{cp.store,cp.epoch,cp.sequence})
		if !ok || last.pledge.head != cp.head { return false }
	}
	epoch, seq := word(u64(cp.epoch)), word(u64(cp.sequence)+1)
	if !change(db,"INSERT INTO events(store_id,epoch,sequence,canonical_event) VALUES(?,?,?,?)",cp.store[:],epoch[:],seq[:],bytes) { return false }
	if entry, present := receipt.(Import); present {
		ord := word(entry.id.ordinal)
		if !change(db,"INSERT INTO denial_imports(store_id,custody_ordinal,record_hash,epoch,sequence) VALUES(?,?,?,?,?)",cp.store[:],ord[:],entry.id.hash[:],epoch[:],seq[:]) ||
		   !change(db,"INSERT INTO import_watermarks(store_id,last_imported_ordinal) VALUES(?,?) ON CONFLICT(store_id) DO UPDATE SET last_imported_ordinal=excluded.last_imported_ordinal",cp.store[:],ord[:]) { return false }
	}
	committed = change(db,"COMMIT")
	return committed
}

// This increment admits exactly one task/proposal. Any additional state-changing kind
// or duplicate binding withholds dispatch. Audit-only records may share the prefix.
NoopHistory :: struct {
	task: Maybe(a.TaskCreated),
	proposal: Maybe(a.ProposalRecorded),
	permit: Maybe(a.AuthorizationRecorded),
	claim: Maybe(a.DispatchClaimed),
	mark: u64,
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
