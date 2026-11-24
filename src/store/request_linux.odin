package store

import a "../audit"
import e "../domain/events"
import r "../replay"
import client "../runtime/client"
import "core:crypto/sha2"

@(private)
REQUEST_DDL :: `CREATE TABLE request_facts (
 store_id BLOB NOT NULL CHECK(length(store_id)=16), epoch BLOB NOT NULL CHECK(length(epoch)=8),
 sequence BLOB NOT NULL CHECK(length(sequence)=8), request_id BLOB NOT NULL CHECK(length(request_id)=16),
 kind BLOB NOT NULL CHECK(kind IN (x'12',x'13')), wire BLOB NOT NULL,
 PRIMARY KEY(store_id,request_id,kind), UNIQUE(store_id,epoch,sequence),
 FOREIGN KEY(store_id,epoch,sequence) REFERENCES events(store_id,epoch,sequence)
) STRICT, WITHOUT ROWID`

@(private)
request_schema :: proc(db: Database) -> bool {
	stmt,ok := bound(db,"SELECT sql FROM sqlite_schema WHERE tbl_name='request_facts' AND sql IS NOT NULL")
	if !ok { return false }
	defer sqlite3_finalize(stmt)
	return sqlite3_step(stmt)==ROW && string(sqlite3_column_text(stmt,0))==REQUEST_DDL && sqlite3_step(stmt)==DONE
}

provision_requests :: proc(w: VerifiedWriter,history: ^r.RequestHistory) -> bool {
	state := cast(^WriterState)w
	if !change(state.db,"BEGIN IMMEDIATE") { return false }
	ok := false
	defer if !ok { _=change(state.db,"ROLLBACK") }
	if !request_schema(state.db) {
		if history.count!=0 || !change(state.db,REQUEST_DDL) { return false }
	}
	ok = request_inventory(w,history) && change(state.db,"COMMIT")
	return ok
}

@(private)
request_fact :: proc(db: Database, wire: []u8, insert: bool) -> bool {
	id := wire[56:72]
	if wire[6]==19 { id=wire[88:104] }
	if insert {
		return change(db,"INSERT INTO request_facts VALUES(?,?,?,?,?,?)",
		              wire[8:24],wire[24:32],wire[32:40],id,wire[6:7],wire)
	}
	stmt,ok := bound(db,"SELECT wire FROM request_facts WHERE store_id=? AND epoch=? AND sequence=? AND request_id=? AND kind=?",
	                 wire[8:24],wire[24:32],wire[32:40],id,wire[6:7])
	if !ok { return false }
	defer sqlite3_finalize(stmt)
	return sqlite3_step(stmt)==ROW && string(column(stmt,0))==string(wire) && sqlite3_step(stmt)==DONE
}

request_inventory :: proc(w: VerifiedWriter,h: ^r.RequestHistory) -> bool {
	state := cast(^WriterState)w
	if !request_schema(state.db) { return false }
	count := 0
	for entry in h.entries[:h.count] {
		v := entry.issued
		bw,be := a.encode_request_issued(v,v.reference.store,v.reference.epoch)
		if be!=.None || !request_fact(state.db,bw[:],false) { return false }
		count+=1
		if x,expired := entry.expiry.(a.RequestExpired); expired {
			wire,err := a.encode_request_expired(x,x.reference.store,x.reference.epoch)
			if err!=.None || !request_fact(state.db,wire[:],false) { return false }
			count+=1
		}
	}
	return read_scalar(state,"SELECT count(*) FROM request_facts")==i64(count)
}

RequestAppend :: struct {before,after: ^r.RequestHistory}
append_request_fact :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,mark: u64,wire: []u8,ctx: ^RequestAppend) -> bool {
	if !client.within_budget(s,4*u64(ctx.before.count+ctx.after.count)+2) { return false }
	next := e.EventRef{cp.store,cp.epoch,cp.sequence+1}
	word_head := cp.head
	if len(wire)<88 || string(wire[len(wire)-32:])!=string(word_head[:]) { return false }
	switch wire[6] {
	case 18:
		v,err := a.decode_request_issued(wire,cp.store,cp.epoch)
		if err!=.None || v.reference!=next { return false }
	case 19:
		v,err := a.decode_request_expired(wire,cp.store,cp.epoch)
		if err!=.None || v.reference!=next { return false }
	case: return false
	}
	h: sha2.Context_256
	sha2.init_256(&h)
	sha2.update(&h,transmute([]u8)string(a.EventDomain))
	sha2.update(&h,wire[:len(wire)-32])
	digest: [32]u8
	sha2.final(&h,digest[:])
	_,confirmed := append_pledged(w,s,cp,mark,nil,wire,digest,client.wb_elapsed_ms(),s.deadline,marker=true,request=ctx)
	return confirmed
}
