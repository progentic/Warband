package reconcile

import a "../audit"
import e "../domain/events"
import r "../replay"
import store "../store"
import client "client"
import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import l "core:sys/linux"

@(private)
CompletionHistory :: struct {
	proposal: a.MarkerProposal,
	approval: Maybe(a.MarkerApproval),
	claim: Maybe(a.MarkerClaim),
	observation: Maybe(a.MarkerObservation),
	evaluation: Maybe(a.MarkerEvaluation),
	accepted: Maybe(a.MarkerAccepted),
}

@(private)
completion_history :: proc(s: IntakeSnapshot) -> (CompletionHistory,bool) {
	h: CompletionHistory
	for row in s.rows[:int(s.cp.sequence)] {
		switch row.bytes[6] {
		case 1,8,13:
		case 11:
			v,err := a.decode_marker_proposal(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.proposal.reference.sequence!=0 { return {},false }
			h.proposal=v
		case 12:
			v,err := a.decode_marker_approval(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.approval!=nil { return {},false }
			h.approval=v
		case 14:
			v,err := a.decode_marker_claim(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.claim!=nil { return {},false }
			h.claim=v
		case 15:
			v,err := a.decode_marker_observation(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.observation!=nil { return {},false }
			h.observation=v
		case 16:
			v,err := a.decode_marker_evaluation(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.evaluation!=nil { return {},false }
			h.evaluation=v
		case 17:
			v,err := a.decode_marker_accepted(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None || h.accepted!=nil { return {},false }
			h.accepted=v
		case: return {},false
		}
	}
	return h,h.proposal.reference.sequence!=0 && len(s.replay.tasks)==1 && s.replay.tasks[0].marker
}

@(private)
fresh_evidence :: proc(s: IntakeSnapshot) -> (e.EvidenceId,bool) {
	id: e.EvidenceId
	n,err := l.getrandom(id[:],{})
	if err!=.NONE || n!=len(id) || id==(e.EvidenceId{}) { return {},false }
	for row in s.rows[:int(s.cp.sequence)] {
		prior: e.EvidenceId
		switch row.bytes[6] {
		case 1:
			v,de := a.decode_task_created(row.bytes,row.ref.store,row.ref.epoch); if de!=.None { return {},false }; prior=v.evidence
		case 12:
			v,de := a.decode_marker_approval(row.bytes,row.ref.store,row.ref.epoch); if de!=.None { return {},false }; prior=v.evidence
		case 13:
			v,de := a.decode_marker_permit(row.bytes,row.ref.store,row.ref.epoch); if de!=.None { return {},false }; prior=v.evidence
		case 15:
			v,de := a.decode_marker_observation(row.bytes,row.ref.store,row.ref.epoch); if de!=.None { return {},false }; prior=v.evidence
		case 16:
			v,de := a.decode_marker_evaluation(row.bytes,row.ref.store,row.ref.epoch); if de!=.None { return {},false }; prior=v.evidence
		case:
		}
		if prior==id { return {},false }
	}
	return id,true
}

@(private)
completion_directory :: proc(fd: l.Fd,p: a.MarkerProposal) -> bool {
	if fd<0 { return false }
	held,ok := private_dir(fd)
	if !ok || u64(held.dev)!=p.device || u64(held.ino)!=p.inode { return false }
	parent,err := l.open("attempts",DirectoryFlags)
	if err!=.NONE { return false }
	defer l.close(parent)
	if _,secure := private_dir(parent); !secure { return false }
	p := p
	named,matched := attempt_dir(parent,&p,false,unused=false)
	if named>=0 { l.close(named) }
	return matched
}

@(private)
completion_probe :: proc() -> u8 {
	when !COMPLETION_PROOF { return 0 }
	st: l.Stat
	fd,err := l.open("completion.probe",{.NOFOLLOW,.CLOEXEC,.NONBLOCK})
	if err!=.NONE { return 0 }
	defer l.close(fd)
	if l.fstat(fd,&st)!=.NONE || !l.S_ISREG(st.mode) || st.uid!=0 || st.nlink!=1 || transmute(u32)st.mode&0o022!=0 || st.size!=1 { return 0 }
	b: [2]u8
	n,re := l.read(fd,b[:])
	return b[0] if re==.NONE && n==1 else 0
}

@(private)
inspect_marker :: proc(fd: l.Fd) -> (a.MarkerEntry,u64,[32]u8) {
	marker,err := l.openat(fd,"marker",{.NOFOLLOW,.CLOEXEC,.NONBLOCK})
	if err==.ENOENT { return .Absent,0,{} }
	if err!=.NONE { return .InspectionIncomplete,0,{} }
	defer l.close(marker)
	st: l.Stat
	if l.fstat(marker,&st)!=.NONE { return .InspectionIncomplete,0,{} }
	if !l.S_ISREG(st.mode) { return .Nonregular,0,{} }
	if st.size<0 { return .InspectionIncomplete,0,{} }
	if u64(st.size)>a.MarkerPayloadLimit { return .Oversized,u64(st.size),{} }
	data: [a.MarkerPayloadLimit+1]u8
	at := 0
	for {
		n,re := l.read(marker,data[at:])
		if re!=.NONE || n<0 { return .InspectionIncomplete,0,{} }
		at+=n
		if n==0 { break }
		if at>int(st.size) { return .InspectionIncomplete,0,{} }
	}
	if at!=int(st.size) { return .InspectionIncomplete,0,{} }
	hash: sha2.Context_256
	sha2.init_256(&hash)
	sha2.update(&hash,data[:at])
	digest: [32]u8
	sha2.final(&hash,digest[:])
	return .Regular,u64(at),digest
}

@(private)
record_marker_observation :: proc(order: ^WorkerOrder,p: a.MarkerProposal,outcome: WorkerOutcome,_arena: ^mem.Arena) -> (result: Threshold) {
	when COMPLETION_PROOF {
		if completion_probe()=='d' && order.fd>=0 { l.close(order.fd); order.fd=-1 }
	}
	stopped := outcome.stopped==1
	control := stopped && outcome.writer_closed==1 && completion_directory(order.fd,p)
	entry,length,digest := a.MarkerEntry.Unassessed,u64(0),[32]u8{}
	if control { entry,length,digest=inspect_marker(order.fd) }
	delivery := a.MarkerDelivery(outcome.delivery)
	if delivery<.ReplyReceived || delivery>.Unknown { delivery=.Unknown }
	root,cust,trusted := intake_configuration()
	if !trusted { return .CompletionUnconfirmed }
	start := client.wb_elapsed_ms()
	if start<0 { return .CompletionUnconfirmed }
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return .CompletionUnconfirmed }
	defer client.wb_release_gate(gate)
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return .CompletionUnconfirmed }
	result = .CompletionUnconfirmed
	defer if !store.close_writer(&w) { result=.CompletionUnconfirmed }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	if !store.limit_writer_cache(w) { return result }
	snap,status := intake_snapshot(w,&s,root)
	h,valid := completion_history(snap)
	claim,claimed := h.claim.(a.MarkerClaim)
	if status!=.Ready || !valid || !claimed || claim.reference!=order.claim || h.observation!=nil ||
	   snap.replay.tasks[0].task_version!=1 || snap.replay.tasks[0].control_revision!=2 || !snap.replay.tasks[0].consumed { return result }
	evidence,unique := fresh_evidence(snap)
	stamp := client.wb_recorded_us()
	if !unique || stamp<0 { return result }
	v := a.MarkerObservation{reference={s.store,s.epoch,snap.cp.sequence+1},claim=order.claim,recorded_time=u64(stamp),
	                         evidence=evidence,delivery=delivery,worker_stopped=stopped,directory_control=control,
	                         entry=entry,observed_length=length,observed_hash=digest,previous_head=snap.cp.head}
	cp,confirmed := store.append_intake(w,&s,snap.cp,snap.mark,v,s.deadline)
	if !confirmed { return result }
	fmt.println("ObservationRef",string(hex.encode(cp.store[:])),cp.epoch,cp.sequence)
	return .Eligible
}

@(private)
recover_completion :: proc(_arena: ^mem.Arena) -> (recovered: bool,result: Threshold) {
	root,cust,trusted := intake_configuration()
	start := client.wb_elapsed_ms()
	if !trusted || start<0 { return false,.CompletionUnconfirmed }
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return false,.CompletionUnconfirmed }
	defer client.wb_release_gate(gate)
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return false,.CompletionUnconfirmed }
	defer if !store.close_writer(&w) { recovered=false; result=.CompletionUnconfirmed }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	if !store.limit_writer_cache(w) { return false,.CompletionUnconfirmed }
	snap,status := intake_snapshot(w,&s,root)
	if status==.Ready { return false,.Eligible }
	if status!=.PendingConfirmation || snap.pending==nil || len(snap.rows)==0 { return false,.CompletionUnconfirmed }
	tail := snap.rows[len(snap.rows)-1]
	if tail.bytes[6]<15 || tail.bytes[6]>17 { return false,.CompletionUnconfirmed }
	p := snap.pending.(e.Pledge)
	if !store.confirm_stored(w,&s,p,nil,s.deadline,marker=true) { return false,.CompletionUnconfirmed }
	return true,.Eligible
}

@(private)
record_evaluation :: proc(_arena: ^mem.Arena) -> (result: Threshold) {
	root,cust,trusted := intake_configuration()
	start := client.wb_elapsed_ms()
	if !trusted || start<0 { return .CompletionUnconfirmed }
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return .CompletionUnconfirmed }
	defer client.wb_release_gate(gate)
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return .CompletionUnconfirmed }
	result = .CompletionUnconfirmed
	defer if !store.close_writer(&w) { result=.CompletionUnconfirmed }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	if !store.limit_writer_cache(w) { return result }
	snap,status := intake_snapshot(w,&s,root)
	h,valid := completion_history(snap)
	if status!=.Ready || !valid { return result }
	if accepted,exists := h.accepted.(a.MarkerAccepted); exists {
		fmt.println("CompletionRef",string(hex.encode(accepted.reference.store[:])),accepted.reference.epoch,accepted.reference.sequence)
		return .Recorded
	}
	if evaluation,exists := h.evaluation.(a.MarkerEvaluation); exists {
		switch evaluation.verdict { case .Verified: return .Eligible; case .Incomplete: return .CompletionIncomplete; case .OperatorReconciliation: return .CompletionReconciliation }
	}
	observation,observed := h.observation.(a.MarkerObservation)
	approval,approved := h.approval.(a.MarkerApproval)
	claim,claimed := h.claim.(a.MarkerClaim)
	if !observed || !approved || !claimed || observation.claim!=claim.reference { return result }
	digest,de := a.digest_marker_observation(observation,s.store,s.epoch)
	verdict := r.marker_verdict(observation,approval.display_length,approval.display_digest)
	evidence,unique := fresh_evidence(snap)
	stamp := client.wb_recorded_us()
	if de!=.None || !unique || stamp<0 { return result }
	v := a.MarkerEvaluation{reference={s.store,s.epoch,snap.cp.sequence+1},observation=observation.reference,claim=claim.reference,
	                        recorded_time=u64(stamp),observation_digest=digest,verdict=verdict,evidence=evidence,previous_head=snap.cp.head}
	cp,confirmed := store.append_intake(w,&s,snap.cp,snap.mark,v,s.deadline)
	if !confirmed { return result }
	fmt.println("EvaluationRef",string(hex.encode(cp.store[:])),cp.epoch,cp.sequence)
	switch verdict { case .Verified: return .Eligible; case .Incomplete: return .CompletionIncomplete; case .OperatorReconciliation: return .CompletionReconciliation }
	return .CompletionUnconfirmed
}

@(private)
record_acceptance :: proc(_arena: ^mem.Arena) -> (result: Threshold) {
	root,cust,trusted := intake_configuration()
	start := client.wb_elapsed_ms()
	if !trusted || start<0 { return .CompletionUnconfirmed }
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return .CompletionUnconfirmed }
	defer client.wb_release_gate(gate)
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return .CompletionUnconfirmed }
	result = .CompletionUnconfirmed
	defer if !store.close_writer(&w) { result=.CompletionUnconfirmed }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	if !store.limit_writer_cache(w) { return result }
	snap,status := intake_snapshot(w,&s,root)
	h,valid := completion_history(snap)
	if status!=.Ready || !valid { return result }
	if accepted,exists := h.accepted.(a.MarkerAccepted); exists {
		if len(snap.replay.tasks)!=1 || !snap.replay.tasks[0].complete { return result }
		fmt.println("CompletionRef",string(hex.encode(accepted.reference.store[:])),accepted.reference.epoch,accepted.reference.sequence)
		return .Recorded
	}
	evaluation,evaluated := h.evaluation.(a.MarkerEvaluation)
	claim,claimed := h.claim.(a.MarkerClaim)
	view := snap.replay.tasks[0]
	if !evaluated || !claimed || evaluation.verdict!=.Verified || view.verdict!=u8(a.MarkerVerdict.Verified) ||
	   view.task_version!=1 || view.control_revision!=2 || view.complete || !view.consumed { return result }
	stamp := client.wb_recorded_us()
	v := a.MarkerAccepted{reference={s.store,s.epoch,snap.cp.sequence+1},evaluation=evaluation.reference,claim=claim.reference,
	                      recorded_time=u64(stamp),expected_task_version=view.task_version,expected_control_revision=view.control_revision,
	                      previous_head=snap.cp.head}
	when COMPLETION_PROOF {
		switch completion_probe() {
		case 'v': v.expected_control_revision-=1
		case 'r': v.claim.sequence-=1
		case:
		}
	}
	n,entropy := l.getrandom(v.transition[:],{})
	if stamp<0 || entropy!=.NONE || n!=len(v.transition) { return result }
	when #config(WARBAND_COMPLETION_ACCEPT_BARRIER,false) {
		if l.kill(l.getpid(),.SIGSTOP)!=.NONE { return result }
	}
	issue := store.append_marker_acceptance(w,&s,root,snap.cp,snap.receipts[:],v)
	fmt.println("AcceptancePreflight",issue)
	switch issue {
	case .None:
	case .Unavailable: return .AcceptanceUnavailable
	case .HistorySegmentInvalid: return .AcceptanceHistorySegmentInvalid
	case .HistoryRowsInvalid: return .AcceptanceHistoryRowsInvalid
	case .HistoryReceiptCountInvalid: return .AcceptanceHistoryReceiptCountInvalid
	case .HistoryReceiptBindingInvalid: return .AcceptanceHistoryReceiptBindingInvalid
	case .HistoryProjectionInvalid: return .AcceptanceHistoryProjectionInvalid
	case .IndexInvalid: return .AcceptanceIndexInvalid
	case .VerdictInvalid: return .AcceptanceVerdictInvalid
	case .VersionsInvalid: return .AcceptanceVersionsInvalid
	case .ReferenceInvalid: return .AcceptanceReferenceInvalid
	case .CommitUnconfirmed: return .AcceptanceCommitUnconfirmed
	}
	fmt.println("CompletionRef",string(hex.encode(v.reference.store[:])),v.reference.epoch,v.reference.sequence)
	return .Completed
}

marker_finalize :: proc(arena: ^mem.Arena) -> Threshold {
	for _ in 0..<4 {
		recovered,state := recover_completion(arena)
		if state!=.Eligible { return state }
		if recovered { continue }
		result := record_evaluation(arena)
		if result!=.Eligible { return result }
		return record_acceptance(arena)
	}
	return .CompletionUnconfirmed
}

marker_completion :: proc(order: ^WorkerOrder,p: a.MarkerProposal,outcome: WorkerOutcome,arena: ^mem.Arena) -> Threshold {
	if observed := record_marker_observation(order,p,outcome,arena); observed!=.Eligible { return observed }
	return marker_finalize(arena)
}
