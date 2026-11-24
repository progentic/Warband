package reconcile

import a "../audit"
import e "../domain/events"
import r "../replay"
import store "../store"
import client "client"
import "core:crypto/sha2"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import l "core:sys/linux"

Threshold :: enum {Unavailable, Claimed, Eligible, NoLiveGrant, ChainMismatch, PayloadMismatch, FingerprintMismatch,
                   PolicyMismatch, TaskMismatch, ControlMismatch, DirectoryLost, DirectoryMismatch, Occupied,
                   Expired, OperationDeadline, ReconciliationRequired, RefusalUnconfirmed, WorkerStopped, ExecutionUncertain,
                   Completed, Recorded, CompletionIncomplete, CompletionReconciliation, CompletionUnconfirmed,
                   AcceptanceUnavailable, AcceptanceHistorySegmentInvalid,
                   AcceptanceHistoryRowsInvalid, AcceptanceHistoryReceiptCountInvalid, AcceptanceHistoryReceiptBindingInvalid,
                   AcceptanceHistoryProjectionInvalid, AcceptanceIndexInvalid, AcceptanceVerdictInvalid,
                   AcceptanceVersionsInvalid, AcceptanceReferenceInvalid, AcceptanceCommitUnconfirmed}
// The confirmed handoff moves the original open directory into one bounded order.
@(private)
WorkerRequest :: struct {
	tag: [4]u8, length: u32, device, inode: u64, deadline: i64,
	claim: [32]u8, attempt,capability,directory: [16]u8, binding,digest: [32]u8, payload: [4096]u8,
}
#assert(offset_of(WorkerRequest,payload)==176)
@(private)
WorkerOutcome :: struct {delivery,stopped,writer_closed,effect: u8}
@(private)
WorkerOrder :: struct {fd: l.Fd, claim: e.EventRef, request: WorkerRequest}
COMPLETION_PROOF :: #config(WARBAND_COMPLETION_PROOF,false)
when COMPLETION_PROOF {
	foreign import marker_proof "system:wb_runtime_client_proof"
	foreign marker_proof { wb_execute_marker_proof :: proc(fd: i32, q: ^WorkerRequest, outcome: ^WorkerOutcome) -> i32 --- }
} else {
	foreign import marker_native "system:wb_runtime_client"
	foreign marker_native { wb_execute_marker :: proc(fd: i32, q: ^WorkerRequest, outcome: ^WorkerOutcome) -> i32 --- }
}

@(private)
execute_marker :: proc(fd: i32,q: ^WorkerRequest,outcome: ^WorkerOutcome) -> i32 {
	when COMPLETION_PROOF { return wb_execute_marker_proof(fd,q,outcome) }
	else { return wb_execute_marker(fd,q,outcome) }
}

@(private)
MarkerOffer :: struct {
	proposal: a.MarkerProposal,
	fingerprint, payload_digest: [32]u8,
	task,control: u64, // expectations for this call, distinct from the original proposal versions
}

@(private)
dispatch_directory :: proc(prepared: ^PreparedProposal,p: a.MarkerProposal) -> Threshold {
	if prepared==nil || prepared.directory_fd<0 { return .DirectoryLost }
	held,ok := private_dir(prepared.directory_fd)
	if !ok || u64(held.dev)!=p.device || u64(held.ino)!=p.inode { return .DirectoryLost }
	parent,err := l.open("attempts",DirectoryFlags)
	if err!=.NONE { return .DirectoryMismatch }
	defer l.close(parent)
	if _,secure := private_dir(parent); !secure { return .DirectoryMismatch }
	p := p
	fd,matched := attempt_dir(parent,&p,false,unused=false)
	if !matched { return .DirectoryMismatch }
	defer l.close(fd)
	st: l.Stat
	#partial switch l.fstatat(prepared.directory_fd,"marker",&st,{.SYMLINK_NOFOLLOW}) {
	case .ENOENT: return .Eligible
	case .NONE: return .Occupied
	case: return .DirectoryLost
	}
}

@(private)
offer_digest :: proc(q: ^MarkerOffer,related: e.EventRef) -> ([32]u8,bool) {
	wire,err := a.encode_marker_proposal(q.proposal,related.store,related.epoch)
	if err!=.None { return {},false }
	ref := related
	versions: [16]u8
	endian.put_u64(versions[:8],.Little,u64(ref.epoch))
	endian.put_u64(versions[8:],.Little,u64(ref.sequence))
	hash: sha2.Context_256
	sha2.init_256(&hash)
	sha2.update(&hash,transmute([]u8)string("warband.marker.dispatch.v1\x00"))
	sha2.update(&hash,ref.store[:])
	sha2.update(&hash,versions[:])
	sha2.update(&hash,wire.data[:wire.length])
	sha2.update(&hash,q.fingerprint[:])
	sha2.update(&hash,q.payload_digest[:])
	endian.put_u64(versions[:8],.Little,q.task)
	endian.put_u64(versions[8:],.Little,q.control)
	sha2.update(&hash,versions[:])
	out: [32]u8
	sha2.final(&hash,out[:])
	return out,true
}

@(private)
marker_checks :: proc(h: ^ReviewHistory,view: r.Projection,grant: ^LiveGrant,prepared: ^PreparedProposal,
                      q: ^MarkerOffer,policy: u64,claimed: bool) -> Threshold {
	approval,approved := h.decision.(a.MarkerApproval)
	permit,permitted := h.permit.(a.MarkerPermit)
	p := &h.proposal
	if !approved || !permitted || !a.marker_approval_matches(approval,p^,p.reference.store,p.reference.epoch) ||
	   permit.approval!=approval.reference || grant.permit!=permit.reference || grant.capability!=permit.capability ||
	   grant.attempt!=p.attempt || view.consumed!=claimed || view.revoked || view.complete || view.disposition!=0 { return .ChainMismatch }
	claim,exists := h.claim.(a.MarkerClaim)
	if exists!=claimed || (claimed && (claim.reference!=grant.claim || claim.permit!=permit.reference ||
	   claim.capability!=grant.capability || claim.attempt!=grant.attempt || claim.fingerprint!=approval.fingerprint)) { return .ChainMismatch }
	if q.proposal.length!=p.length || string(q.proposal.payload[:p.length])!=string(p.payload[:p.length]) { return .PayloadMismatch }
	f,d,issue := a.marker_proposal_hashes(q.proposal,p.reference.store,p.reference.epoch)
	if issue!=.None || q.proposal.reference!=approval.proposal || f!=approval.fingerprint || q.fingerprint!=f { return .FingerprintMismatch }
	if d!=approval.display_digest || q.payload_digest!=d { return .PayloadMismatch }
	if policy!=2 { return .PolicyMismatch } // the registered marker profile is version 2
	if q.task!=view.task_version { return .TaskMismatch }
	if q.control!=view.control_revision { return .ControlMismatch }
	return dispatch_directory(prepared,p^)
}

@(private)
take_dispatch :: proc(h: ^ReviewHistory,view: r.Projection,slot: ^Maybe(LiveGrant),prepared: ^PreparedProposal,
                      q: ^MarkerOffer,policy: u64,deadline: i64) -> Threshold {
	grant,present := slot^.(LiveGrant)
	slot^=nil // a refusal retires this entry too
	if !present { return .NoLiveGrant }
	check := marker_checks(h,view,&grant,prepared,q,policy,true)
	if check!=.Eligible { return check }
	window := check_window(&grant,client.wb_elapsed_ms())
	if window.result!=.Eligible { return .Expired }
	if window.observed>=deadline { return .OperationDeadline }
	return .Eligible
}

@(private)
record_gate_refusal :: proc(w: store.VerifiedWriter,s: ^client.Session,snap: ^IntakeSnapshot,related: e.EventRef,
                           digest: [32]u8,result: Threshold,deadline: i64) -> Threshold {
	reason: u16 = 9 // invalid evidence
	#partial switch result {
	case .Expired,.OperationDeadline: reason=5
	case .PolicyMismatch: reason=2
	case .TaskMismatch,.ControlMismatch: reason=4
	case .DirectoryMismatch: reason=3
	}
	stamp := client.wb_recorded_us()
	if stamp<0 { return .RefusalUnconfirmed }
	v := a.RejectionRecorded{reference={s.store,s.epoch,snap.cp.sequence+1},previous_head=snap.cp.head,recorded_time=u64(stamp),
	                         producer=2,stage=3,reason=reason,related=related,rejected_input_digest=digest}
	if _,confirmed := store.append_intake(w,s,snap.cp,snap.mark,v,deadline); !confirmed { return .RefusalUnconfirmed }
	return result
}

@(private)
gate_locked :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,prepared: ^PreparedProposal,
                    slot: ^Maybe(LiveGrant),q: ^MarkerOffer,policy: u64,claimed: bool,deadline: i64,order: ^WorkerOrder) -> Threshold {
	snap,state := intake_snapshot(w,s,root)
	if state!=.Ready { return .ReconciliationRequired }
	h,valid := review_history(snap)
	if !valid { return .ReconciliationRequired }
	view := snap.replay.tasks[0]
	grant,present := slot^.(LiveGrant)
	if !present { return .NoLiveGrant }
	related := grant.permit
	if claimed { related=grant.claim }
	digest,ok := offer_digest(q,related)
	if !ok { return .Unavailable }
	if claimed {
		result := take_dispatch(&h,view,slot,prepared,q,policy,deadline)
		if result!=.Eligible { return record_gate_refusal(w,s,&snap,related,digest,result,deadline) }
		// Freeze the request here; the external wait begins only after gate_round closes the writer.
		if order!=nil {
			window := check_window(&grant,client.wb_elapsed_ms())
			if window.result!=.Eligible { return record_gate_refusal(w,s,&snap,related,digest,.Expired,deadline) }
			p := &q.proposal
			req := &order.request
			req.tag={'W','B','M','1'}
			req.length,req.device,req.inode=p.length,p.device,p.inode
			req.deadline=min(deadline,window.cutoff)
			copy(req.claim[:16],related.store[:])
			endian.put_u64(req.claim[16:24],.Little,u64(related.epoch))
			endian.put_u64(req.claim[24:],.Little,u64(related.sequence))
			req.attempt,req.capability,req.directory=cast([16]u8)grant.attempt,cast([16]u8)grant.capability,cast([16]u8)p.directory
			req.binding,req.digest=digest,q.payload_digest
			copy(req.payload[:p.length],p.payload[:p.length])
			order.fd,order.claim,prepared.directory_fd=prepared.directory_fd,related,-1
		}
		fmt.println("BrokerHandoff",string(hex.encode(related.store[:])),related.epoch,related.sequence,
		            string(hex.encode(grant.attempt[:])),string(hex.encode(digest[:])))
		when #config(WARBAND_MARKER_GATE_PROOF,false) {
			again := take_dispatch(&h,view,slot,prepared,q,policy,deadline)
			fmt.println("SecondEvaluation",again)
			if again!=.NoLiveGrant { return .Unavailable }
		}
		return .Eligible
	}
	check := marker_checks(&h,view,&grant,prepared,q,policy,false)
	window := check_window(&grant,client.wb_elapsed_ms())
	if check==.Eligible && window.result!=.Eligible { check=.Expired }
	if check!=.Eligible {
		slot^=nil
		return record_gate_refusal(w,s,&snap,related,digest,check,deadline)
	}
	stamp := client.wb_recorded_us()
	if stamp<0 { return .Unavailable }
	v := a.MarkerClaim{reference={s.store,s.epoch,snap.cp.sequence+1},previous_head=snap.cp.head,recorded_time=u64(stamp),
	                   permit=grant.permit,attempt=grant.attempt,capability=grant.capability,expected_task_version=q.task,
	                   expected_control_revision=q.control,fingerprint=q.fingerprint}
	head,confirmed := store.append_intake(w,s,snap.cp,snap.mark,v,min(deadline,window.cutoff))
	if !confirmed { return .ReconciliationRequired }
	grant.claim=v.reference
	if check_window(&grant,client.wb_elapsed_ms()).result!=.Eligible {
		slot^=nil
		snap.cp=head
		refused,encoded := offer_digest(q,v.reference)
		if !encoded { return .RefusalUnconfirmed }
		return record_gate_refusal(w,s,&snap,v.reference,refused,.Expired,deadline)
	}
	slot^=grant
	return .Claimed
}

@(private)
gate_round :: proc(prepared: ^PreparedProposal,slot: ^Maybe(LiveGrant),q: ^MarkerOffer,supplied_policy: Maybe(u64),
                   operator: u32,admission: i64,claimed: bool,arena: ^mem.Arena,order: ^WorkerOrder=nil) -> Threshold {
	temp := mem.begin_arena_temp_memory(arena)
	defer mem.end_arena_temp_memory(temp)
	context.allocator=mem.arena_allocator(arena)
	root,cust,trusted := intake_configuration()
	registered: u32
	start := client.wb_elapsed_ms()
	if !trusted || cust==operator || client.wb_approval_roles(1,&registered)!=0 || registered!=operator ||
	   start<admission || start>=admission+180_000 { return .Unavailable }
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return .Unavailable }
	defer client.wb_release_gate(gate)
	locked := client.wb_elapsed_ms()
	if locked<start || locked-start>=5_000 { return .Unavailable }
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return .Unavailable }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	result := Threshold.Unavailable
	if store.limit_writer_cache(w) {
		policy: u64=2 // read the registered policy at each gate, independent of the offered versions
		when #config(WARBAND_MARKER_GATE_PROOF,false) {
			if observation,supplied := supplied_policy.(u64); supplied && claimed { policy=observation }
		}
		result=gate_locked(w,&s,root,prepared,slot,q,policy,claimed,min(start+30_000,admission+180_000),order)
	}
	if !store.close_writer(&w) || s.exhausted { return .ReconciliationRequired }
	return result
}

marker_threshold :: proc(prepared: ^PreparedProposal,slot: ^Maybe(LiveGrant),operator: u32,admission: i64,arena: ^mem.Arena,execute:=false,complete:=false) -> Threshold {
	defer slot^=nil
	if prepared==nil || slot^==nil { return .NoLiveGrant }
	p := &prepared.proposal
	f,d,err := a.marker_proposal_hashes(p^,p.reference.store,p.reference.epoch)
	if err!=.None || p.expected_control_revision>max(u64)-2 { return .Unavailable }
	q := MarkerOffer{p^,f,d,p.expected_task_version,p.expected_control_revision+1}
	supplied_policy: Maybe(u64)
	first := gate_round(prepared,slot,&q,nil,operator,admission,false,arena)
	if first!=.Claimed { return first }
	q.control+=1
	when #config(WARBAND_MARKER_GATE_PROOF,false) {
		if l.kill(l.getpid(),.SIGSTOP)!=.NONE { return .Unavailable }
		fd,opened := l.open("gate-proof-input",{.NOFOLLOW,.CLOEXEC,.NONBLOCK})
		if opened!=.NONE { return .Unavailable }
		defer l.close(fd)
		code: [2]u8
		n,re := l.read(fd,code[:])
		if n!=1 || re!=.NONE { return .Unavailable }
		switch code[0] {
		case 0: // unchanged, including real filesystem cases
		case 1:
			if q.proposal.length==0 { return .Unavailable }
			q.proposal.payload[0]~=1
		case 2: q.proposal.proposal[0]~=1
		case 3: supplied_policy=u64(1)
		case 4: q.task-=1
		case 5: q.control-=1
		case 6:
			if l.close(prepared.directory_fd)!=.NONE { return .Unavailable }
			prepared.directory_fd=-1
		case: return .Unavailable
		}
	}
	order := WorkerOrder{fd=-1}
	defer if order.fd>=0 { l.close(order.fd) }
	result := gate_round(prepared,slot,&q,supplied_policy,operator,admission,true,arena,&order if execute || complete else nil)
	if (!execute && !complete) || result!=.Eligible { return result }
	if order.fd<0 { return .ExecutionUncertain }
	outcome: WorkerOutcome
	executed := execute_marker(i32(order.fd),&order.request,&outcome)==1
	if complete { return marker_completion(&order,p^,outcome,arena) }
	if !executed { return .ExecutionUncertain }
	return .WorkerStopped
}
