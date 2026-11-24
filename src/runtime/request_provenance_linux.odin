package reconcile

import a "../audit"
import e "../domain/events"
import m "../model"
import r "../replay"
import store "../store"
import client "client"
import "core:encoding/endian"
import "core:encoding/hex"
import l "core:sys/linux"

@(private)
RequestMark :: "user.warband.request.v1"
@(private)
CommitMark :: "user.warband.commit.v1"

@(private)
read_mark :: proc(fd:l.Fd,name:cstring,buf:[]u8) -> int {
	return l.syscall(l.SYS_fgetxattr,fd,cast(rawptr)name,raw_data(buf),len(buf))
}

@(private)
create_mark :: proc(fd:l.Fd,name:cstring,value:[]u8) -> bool {
	if l.fsetxattr(fd,name,raw_data(value),uint(len(value)),1)!=.NONE { return false }
	if string(name)==RequestMark { store.request_probe(11,"xattr-set") }
	return l.fsync(fd)==.NONE
}

// The time witness is written only after a timely COMMIT return. If the issuer
// dies in between, recovery cannot infer the time from the pending pledge.
@(private)
commit_mark :: proc(id:[16]u8,digest:[32]u8,upper:u64) -> (b:[56]u8) {
	id,digest:=id,digest
	copy(b[:16],id[:])
	copy(b[16:48],digest[:])
	endian.put_u64(b[48:],.Little,upper)
	return
}

@(private)
check_pair :: proc(w:store.VerifiedWriter,snap:IntakeSnapshot,h:^r.RequestHistory) -> (Maybe([16]u8),bool) {
	count:=store.consumption_count(w)
	if count<0 || count>1 { return nil,false }
	parent,pe:=l.open("attempts",DirectoryFlags)
	if pe!=.NONE { return nil,false }
	defer l.close(parent)
	if _,ok:=private_dir(parent); !ok { return nil,false }
	entry,ok:=attempt_entry(parent)
	if !ok { return nil,false }
	wire:[]u8
	for row in snap.rows {
		if row.bytes[6]!=11 { continue }
		if wire!=nil { return nil,false }
		wire=row.bytes
	}
	if wire==nil {
		return nil,count==0 && entry=="" && len(snap.replay.tasks)==0
	}
	proposal,err:=a.decode_marker_proposal(wire,snap.cp.store,snap.cp.epoch)
	if err!=.None || entry!=string(hex.encode(proposal.directory[:])) { return nil,false }
	fd,opened:=attempt_dir(parent,&proposal,false,false)
	if !opened { return nil,false }
	defer l.close(fd)
	id:[16]u8
	n:=read_mark(fd,RequestMark,id[:])
	if n == -int(l.Errno.ENODATA) {
		unused:[56]u8
		return nil,count==0 && h.count==0 && read_mark(fd,CommitMark,unused[:]) == -int(l.Errno.ENODATA)
	}
	if n!=len(id) || count!=1 { return nil,false }
	witness:=r.find_request(h,id)
	if witness==nil || witness.expiry!=nil { return nil,false }
	issue:=witness.issued
	example,known:=m.catalog_entry(issue.revision,m.Catalog_Id(issue.catalog_id))
	if !known || example.payload!=string(proposal.payload[:proposal.length]) ||
	   !store.consumption_row(w,issue,wire,false) { return nil,false }
	proof:[56]u8
	if read_mark(fd,CommitMark,proof[:])!=len(proof) { return nil,false }
	upper,_:=endian.get_u64(proof[48:],.Little)
	digest,de:=a.digest_marker_proposal(proposal,snap.cp.store,snap.cp.epoch)
	if de!=.None || upper<issue.start_ms || upper>=issue.deadline_ms || proof!=commit_mark(id,digest,upper) ||
	   l.fsync(fd)!=.NONE { return nil,false }
	return id,true
}

@(private)
verify_pending_pair :: proc(w:store.VerifiedWriter,s:^client.Session,root:e.Checkpoint,snap:IntakeSnapshot,p:e.Pledge) -> bool {
	segments:=[?]r.Segment{{rows=snap.rows}}
	if !client.within_budget(s,36*u64(len(snap.rows))+2) { return false }
	view,h:=r.project_requests(root,{s.store,s.epoch,p.sequence,p.head},nil,segments[:],snap.receipts[:])
	if view.error!=.None || view.readiness!=.Ready || len(view.tasks)!=1 || !view.tasks[0].marker ||
	   view.tasks[0].task_version!=1 || view.tasks[0].control_revision!=0 ||
	   !catalog_matches(&h) || !store.request_inventory(w,&h) { return false }
	id,ok:=check_pair(w,snap,&h)
	return ok && id!=nil
}

@(private)
witness_model_commit :: proc(w:store.VerifiedWriter,s:^client.Session,model:^store.ModelWrite,p:e.Pledge,end:i64) -> bool {
	proof:=commit_mark(model.issued.id,p.digest,u64(end))
	if !create_mark(model.fd,CommitMark,proof[:]) { return false }
	h:r.RequestHistory
	snap,status:=intake_snapshot(w,s,model.root,&h)
	if status!=.PendingConfirmation || snap.pending!=p { return false }
	store.request_probe(11,"time-synced")
	return verify_pending_pair(w,s,model.root,snap,p)
}
