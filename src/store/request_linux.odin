package store

import a "../audit"
import e "../domain/events"
import r "../replay"
import client "../runtime/client"
import "core:crypto/sha2"
@(require) import "core:os"
@(require) import l "core:sys/linux"

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
	if consumption_count(w)<0 {
		if history.count!=0 || !change(state.db,CONSUMPTION_DDL) { return false }
	}
	ok = consumption_count(w)==0 && request_inventory(w,history) && change(state.db,"COMMIT")
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

@(private)
CONSUMPTION_DDL :: `CREATE TABLE consumed_requests (
 store_id BLOB NOT NULL CHECK(length(store_id)=16), request_id BLOB NOT NULL CHECK(length(request_id)=16),
 epoch BLOB NOT NULL CHECK(length(epoch)=8), sequence BLOB NOT NULL CHECK(length(sequence)=8),
 catalog_id BLOB NOT NULL CHECK(length(catalog_id)=4), payload_digest BLOB NOT NULL CHECK(length(payload_digest)=32),
 event_digest BLOB NOT NULL CHECK(length(event_digest)=32), fingerprint BLOB NOT NULL CHECK(length(fingerprint)=32),
 PRIMARY KEY(store_id,request_id), UNIQUE(store_id,epoch,sequence),
 FOREIGN KEY(store_id,epoch,sequence) REFERENCES events(store_id,epoch,sequence)
) STRICT, WITHOUT ROWID`

consumption_count :: proc(w: VerifiedWriter) -> i64 {
	state:=cast(^WriterState)w
	stmt,ok:=bound(state.db,"SELECT sql FROM sqlite_schema WHERE tbl_name='consumed_requests' AND sql IS NOT NULL")
	if !ok { return -1 }
	defer sqlite3_finalize(stmt)
	if sqlite3_step(stmt)!=ROW || string(sqlite3_column_text(stmt,0))!=CONSUMPTION_DDL || sqlite3_step(stmt)!=DONE { return -1 }
	n,found:=read_scalar(state,"SELECT count(*) FROM consumed_requests").(i64)
	return n if found else -1
}

ModelWrite :: struct {
	issued: a.RequestIssued,
	history: ^r.RequestHistory,
	root: e.Checkpoint,
	fd: l.Fd,
	witness: proc(w:VerifiedWriter,s:^client.Session,model:^ModelWrite,p:e.Pledge,end:i64) -> bool,
}

in_request_window :: proc(issued: a.RequestIssued,now: i64) -> bool {
	return now>=0 && u64(now)>=issued.start_ms && u64(now)<issued.deadline_ms
}

@(private)
model_write_eligible :: proc(w: VerifiedWriter,model: ^ModelWrite,wire: []u8) -> bool {
	entry:=r.find_request(model.history,model.issued.id)
	return (wire[6]==1 || wire[6]==11) && entry!=nil && entry.issued==model.issued && entry.expiry==nil &&
	       in_request_window(model.issued,client.wb_elapsed_ms()) && request_inventory(w,model.history) && consumption_count(w)==0
}

// Regenerate every binding from the witnessed issuance and the canonical proposal.
consumption_row :: proc(w: VerifiedWriter, issued: a.RequestIssued,wire: []u8,insert: bool) -> bool {
	ref:=issued.reference
	proposal,decoded:=a.decode_marker_proposal(wire,ref.store,ref.epoch)
	if decoded!=.None || proposal.reference.sequence<=ref.sequence { return false }
	f,payload,fe:=a.marker_proposal_hashes(proposal,ref.store,ref.epoch)
	digest,de:=a.digest_marker_proposal(proposal,ref.store,ref.epoch)
	if fe!=.None || de!=.None || payload!=issued.payload_digest { return false }
	v:=issued
	catalog:=word(u64(v.catalog_id))
	db:=cast(^WriterState)w
	if insert {
		return change(db.db,"INSERT INTO consumed_requests VALUES(?,?,?,?,?,?,?,?)",wire[8:24],v.id[:],
		              wire[24:32],wire[32:40],catalog[:4],payload[:],digest[:],f[:])
	}
	stmt,ok:=bound(db.db,"SELECT 1 FROM consumed_requests WHERE store_id=? AND request_id=? AND epoch=? AND sequence=? AND catalog_id=? AND payload_digest=? AND event_digest=? AND fingerprint=?",
	               wire[8:24],v.id[:],wire[24:32],wire[32:40],catalog[:4],payload[:],digest[:],f[:])
	if !ok { return false }
	defer sqlite3_finalize(stmt)
	return sqlite3_step(stmt)==ROW && sqlite3_step(stmt)==DONE
}

// The caller supplies the runtime-owned directory witness. A true result always
// means the stored deadline proof and pair were verified and custody confirmed.
append_model_pair :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,mark: u64,
                          model: ^ModelWrite,v: a.MarkerProposal) -> (e.Checkpoint,bool) {
	if v.reference!=(e.EventRef{cp.store,cp.epoch,cp.sequence+1}) || v.previous_head!=cp.head { return {},false }
	b,err:=a.encode_marker_proposal(v,cp.store,cp.epoch)
	digest,de:=a.digest_marker_proposal(v,cp.store,cp.epoch)
	start:=client.wb_elapsed_ms()
	if err!=.None || de!=.None || !in_request_window(model.issued,start) ||
	   !client.within_budget(s,4*u64(model.history.count)+2) { return {},false }
	return append_pledged(w,s,cp,mark,nil,b.data[:b.length],digest,start,i64(model.issued.deadline_ms),marker=true,model=model)
}

// The production binary has no selector or signal path. The proof binary
// stops at real boundaries so the external harness controls process death.
RequestProof :: #config(WARBAND_REQUEST_PROOF,false)
request_proof_selected :: proc(kind:u8,stage:string) -> bool {
	when RequestProof {
		buf:[64]u8
		label:=os.get_env(buf[:],"WB_REQUEST_EDGE")
		expected:=""
		switch kind {
		case 1: expected="01."
		case 11: expected="11."
		case 18: expected="18."
		case 19: expected="19."
		case: return false
		}
		return len(label)>3 && label[:3]==expected && label[3:]==stage
	} else { return false }
}
request_probe :: proc(kind:u8,stage:string) {
	when RequestProof {
		if request_proof_selected(kind,stage) { assert(l.kill(l.getpid(),.SIGSTOP)==.NONE) }
	}
}
