package reconcile

import a "../audit"
import e "../domain/events"
import m "../model"
import r "../replay"
import store "../store"
import client "client"
import "core:encoding/hex"
import l "core:sys/linux"

// The session holds a separate directory flock for its lifetime. A new caller
// cannot declare session loss while the issuer or an inherited lease is alive.
RequestSession :: struct {lease: l.Fd, id, boot: [16]u8}
RequestOperation :: enum {Provision, Issue, Cancel, ExpireDue, Recover, Admit, AdmitSelection}
RequestStatus :: enum {Ready, Issued, Expired, Recorded, Unknown, Unavailable, Busy, Reconciliation, Limit, Admitted, Consumed, CandidateRejected}

open_request_session :: proc() -> (RequestSession,bool) {
	operator: u32
	if client.wb_approval_roles(1,&operator)!=0 { return {},false }
	_,_,trusted := intake_configuration()
	if !trusted { return {},false }
	fd,err := l.open("journal",DirectoryFlags)
	if err!=.NONE { return {},false }
	held := false
	defer if !held { l.close(fd) }
	if _,ok := private_dir(fd); !ok || l.flock(fd,{.EX,.NB})!=.NONE { return {},false }
	boot,be := l.open("/proc/sys/kernel/random/boot_id",{.CLOEXEC})
	if be!=.NONE { return {},false }
	defer l.close(boot)
	text: [37]u8
	n,re := l.read(boot,text[:])
	if re!=.NONE || n!=37 || text[36]!='\n' { return {},false }
	raw: [32]u8
	i:=0
	for ch,j in text[:36] {
		if j==8 || j==13 || j==18 || j==23 {
			if ch!='-' { return {},false }
			continue
		}
		raw[i]=ch
		i+=1
	}
	bytes,ok := hex.decode(raw[:])
	defer delete(bytes)
	if !ok || len(bytes)!=16 { return {},false }
	v := RequestSession{lease=fd}
	copy(v.boot[:],bytes)
	random,ge := l.getrandom(v.id[:],{})
	if ge!=.NONE || random!=16 || v.id==([16]u8{}) || v.boot==([16]u8{}) { return {},false }
	held=true
	return v,true
}

@(private)
catalog_matches :: proc(h: ^r.RequestHistory) -> bool {
	for entry in h.entries[:h.count] {
		v:=entry.issued
		example,ok:=m.catalog_entry(v.revision,m.Catalog_Id(v.catalog_id))
		if !ok || m.catalog_digest(example.payload)!=v.payload_digest { return false }
	}
	return true
}

@(private)
pending_requests :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,snap: IntakeSnapshot) -> RequestStatus {
	p,present:=snap.pending.(e.Pledge)
	if !present || len(snap.rows)==0 { return .Reconciliation }
	tail:=snap.rows[len(snap.rows)-1]
	if tail.bytes[6]==11 {
		if verify_pending_pair(w,s,root,snap,p) && store.confirm_stored(w,s,p,nil,s.deadline,marker=true,requests=true) { return .Recorded }
		return .Reconciliation
	}
	if tail.bytes[6]!=18 && tail.bytes[6]!=19 { return .Reconciliation }
	segments:=[?]r.Segment{{rows=snap.rows}}
	cp:=e.Checkpoint{s.store,s.epoch,p.sequence,p.head}
	if !client.within_budget(s,35*u64(len(snap.rows))) { return .Limit }
	view,h:=r.project_requests(root,cp,nil,segments[:],snap.receipts[:])
	if view.error!=.None || view.readiness!=.Ready || !catalog_matches(&h) ||
	   !client.within_budget(s,2*u64(h.count)) || !store.request_inventory(w,&h) { return .Reconciliation }
	if _,consistent:=check_pair(w,snap,&h); !consistent { return .Reconciliation }
	if !store.confirm_stored(w,s,p,nil,s.deadline,marker=true,requests=true) { return .Reconciliation }
	return .Recorded
}

@(private)
expire_request :: proc(w: store.VerifiedWriter,s: ^client.Session,snap: IntakeSnapshot,h: ^r.RequestHistory,
                       entry: r.RequestWitness,reason: a.RequestExpiryReason) -> RequestStatus {
	stamp:=client.wb_recorded_us()
	if stamp<0 || snap.cp.sequence==max(e.Sequence) { return .Unavailable }
	v:=a.RequestExpired{reference={s.store,s.epoch,snap.cp.sequence+1},issuance=entry.issued.reference,
	                    id=entry.issued.id,reason=reason,previous_head=snap.cp.head,recorded_time=u64(stamp)}
	wire,err:=a.encode_request_expired(v,s.store,s.epoch)
	after:=h^
	r.find_request(&after,v.id).expiry=v
	ctx:=store.RequestAppend{h,&after}
	if err!=.None || !store.append_request_fact(w,s,snap.cp,snap.mark,wire[:],&ctx) { return .Reconciliation }
	return .Expired
}

@(private)
request_locked :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,owner: RequestSession,
                       op: RequestOperation,catalog_id: m.Catalog_Id,id: [16]u8,candidate: []u8,
                       selection: m.Validated_Candidate, issuance: ^a.RequestIssued) -> (RequestStatus,[16]u8) {
	h:r.RequestHistory
	snap,status:=intake_snapshot(w,s,root,&h)
	if status==.PendingConfirmation && op==.Recover { return pending_requests(w,s,root,snap),{} }
	if status!=.Ready || !catalog_matches(&h) || snap.replay.receipts_used!=len(snap.receipts) { return .Reconciliation,{} }
	if op==.Provision {
		if len(snap.replay.tasks)!=0 || !store.provision_requests(w,&h) { return .Reconciliation,{} }
		return .Ready,{}
	}
	if !client.within_budget(s,2*u64(h.count)+1) || !store.request_inventory(w,&h) { return .Reconciliation,{} }
	spent,consistent:=check_pair(w,snap,&h)
	if !consistent { return .Reconciliation,{} }
	if op==.Recover {
		for entry in h.entries[:h.count] {
			if spent!=entry.issued.id && entry.expiry==nil && (entry.issued.session!=owner.id || entry.issued.boot!=owner.boot) {
				return expire_request(w,s,snap,&h,entry,.SessionLost),entry.issued.id
			}
		}
		return .Ready,{}
	}
	if op==.Issue {
		if spent!=nil || len(snap.replay.tasks)!=0 { return .Busy,{} }
		if h.count>=len(h.entries) { return .Limit,{} }
		for entry in h.entries[:h.count] {
			if entry.expiry==nil { return .Busy,{} }
		}
		example,ok:=m.catalog_entry(m.CatalogRevision,catalog_id)
		entries:=m.CatalogV1
		if !ok || !m.valid_catalog(entries[:]) { return .Unknown,{} }
		now,stamp:=client.wb_elapsed_ms(),client.wb_recorded_us()
		if now<0 || stamp<0 || now>=s.deadline || now>max(i64)-30_000 { return .Unavailable,{} }
		v:=a.RequestIssued{reference={s.store,s.epoch,snap.cp.sequence+1},recorded_time=u64(stamp),
		                   previous_head=snap.cp.head,boot=owner.boot,session=owner.id,start_ms=u64(now),
		                   deadline_ms=u64(min(now+30_000,s.deadline)),catalog_id=u32(catalog_id),
		                   revision=m.CatalogRevision,payload_digest=m.catalog_digest(example.payload)}
		n,ge:=l.getrandom(v.id[:],{})
		if ge!=.NONE || n!=16 || r.find_request(&h,v.id)!=nil { return .Unavailable,{} }
		wire,err:=a.encode_request_issued(v,s.store,s.epoch)
		after:=h
		after.entries[after.count].issued=v
		after.count+=1
		ctx:=store.RequestAppend{&h,&after}
		if err!=.None || !store.append_request_fact(w,s,snap.cp,snap.mark,wire[:],&ctx) { return .Reconciliation,{} }
		end:=client.wb_elapsed_ms()
		if end<now || u64(end)>=v.deadline_ms { return .Unavailable,{} }
		if issuance!=nil { issuance^=v }
		return .Issued,v.id
	}
	entry:=r.find_request(&h,id)
	if entry==nil { return .Unknown,{} }
	if spent==id { return .Consumed,id }
	if entry.expiry!=nil { return .Expired,id }
	if entry.issued.boot!=owner.boot || entry.issued.session!=owner.id { return .Reconciliation,{} }
	now:=client.wb_elapsed_ms()
	if now<0 || u64(now)<entry.issued.start_ms { return .Unavailable,{} }
	if u64(now)>=entry.issued.deadline_ms { return expire_request(w,s,snap,&h,entry^,.Deadline),id }
	if op==.Admit || op==.AdmitSelection {
		example,ok:=m.catalog_entry(entry.issued.revision,m.Catalog_Id(entry.issued.catalog_id))
		if !ok { return .Reconciliation,{} }
		request_id:m.Request_Id
		issued_id:=id
		copy(request_id[:],hex.encode(issued_id[:]))
		payload:=transmute([]u8)example.payload
		matched:=selection
		if op==.Admit {
			result:=m.validate_candidate(candidate,request_id,{example.id,payload})
			valid: bool
			matched,valid=result.(m.Validated_Candidate)
			if !valid { return .CandidateRejected,{} }
		}
		if matched.request_id!=request_id || matched.example!=example.id || matched.decoded_length!=len(payload) {
			return .CandidateRejected,{}
		}
		parent,pe:=l.open("attempts",DirectoryFlags)
		if pe!=.NONE { return .Reconciliation,{} }
		defer l.close(parent)
		if _,private:=private_dir(parent); !private { return .Reconciliation,{} }
		model:=store.ModelWrite{issued=entry.issued,history=&h}
		accepted,outcome:=intake_locked(w,s,root,parent,payload,i64(entry.issued.deadline_ms),&model)
		if outcome!=.ConfirmedProposal { return .Reconciliation,{} }
		l.close(accepted.directory_fd)
		return .Admitted,id
	}
	if op==.Cancel { return expire_request(w,s,snap,&h,entry^,.Cancelled),id }
	return .Ready,id
}

request_round :: proc(owner:RequestSession, op:RequestOperation, catalog_id:m.Catalog_Id=0,id:[16]u8={},candidate:[]u8=nil,
                      selection:m.Validated_Candidate={}, issuance:^a.RequestIssued=nil) -> (RequestStatus,[16]u8) {
	root,cust,trusted:=intake_configuration()
	start:=client.wb_elapsed_ms()
	if !trusted || start<0 || !store.limit_sqlite() { return .Unavailable,{} }
	s:=client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	gate:=client.wb_writer_gate(IntakeDB)
	if gate<0 { return .Busy,{} }
	defer client.wb_release_gate(gate)
	w,err:=store.open_writer(IntakeDB)
	if err!=.None { return .Unavailable,{} }
	status:=RequestStatus.Unavailable
	output:[16]u8
	confirmed: a.RequestIssued
	if store.limit_writer_cache(w) { status,output=request_locked(w,&s,root,owner,op,catalog_id,id,candidate,selection,&confirmed) }
	if !store.close_writer(&w) { return .Unavailable,{} }
	if status==.Issued && issuance!=nil { issuance^=confirmed }
	return status,output
}
