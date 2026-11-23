package reconcile

import a "../audit"
import e "../domain/events"
import r "../replay"
import store "../store"
import client "client"
import "core:encoding/endian"
import "core:mem"
import l "core:sys/linux"

// One operator packet carries the displayed Ref, fingerprint, length, payload
// digest and decision. Peer identity is read independently from the socket.
DecisionPacket :: [101]u8
decision_packet :: proc(p: a.MarkerProposal,d: a.MarkerDecision) -> (DecisionPacket,bool) {
	p := p
	f,h,err := a.marker_proposal_hashes(p,p.reference.store,p.reference.epoch)
	b: DecisionPacket
	copy(b[:16],p.reference.store[:])
	endian.put_u64(b[16:24],.Little,u64(p.reference.epoch))
	endian.put_u64(b[24:32],.Little,u64(p.reference.sequence))
	copy(b[32:64],f[:])
	endian.put_u32(b[64:68],.Little,p.length)
	copy(b[68:100],h[:])
	b[100]=u8(d)
	return b,err==.None && (d==.Approve || d==.Reject)
}

ReviewStatus :: enum u8 {Withheld, Display, Permitted, Rejected, Recorded, BindingMismatch, DecisionConflict,
                         DirectoryHold, ReconciliationRequired, Uncertain, Unavailable, LockUnavailable, RecoveryLimitExceeded}
ReviewResult :: struct {status: ReviewStatus, decision: e.EventRef, grant: Maybe(LiveGrant)}
ReviewDisplay :: struct {proposal: a.MarkerProposal, checkpoint: e.Checkpoint, task_version, control_revision: u64, consumed: bool}
@(private)
ReviewHistory :: struct {proposal: a.MarkerProposal, task_evidence: e.EvidenceId, decision: Maybe(a.MarkerApproval), permit: Maybe(a.MarkerPermit), claim: Maybe(a.MarkerClaim)}

// Replay has already validated role, scope, uniqueness, versions and digest chain.
// This endpoint accepts only the single marker intake and its first decision/permit.
@(private)
review_history :: proc(s: IntakeSnapshot) -> (ReviewHistory,bool) {
	h: ReviewHistory
	if len(s.replay.tasks)!=1 || !s.replay.tasks[0].marker || s.replay.receipts_used!=len(s.receipts) { return {},false }
	for row in s.rows[:int(s.cp.sequence)] {
		switch row.bytes[6] {
		case 8:
		case 1:
			t,err := a.decode_task_created(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None { return {},false }
			h.task_evidence=t.evidence
		case 11:
			if h.proposal.reference.sequence!=0 { return {},false }
			p,err := a.decode_marker_proposal(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None { return {},false }
			h.proposal=p
		case 12:
			v,err := a.decode_marker_approval(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None { return {},false }
			h.decision=v
		case 13:
			v,err := a.decode_marker_permit(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None { return {},false }
			h.permit=v
		case 14:
			v,err := a.decode_marker_claim(row.bytes,row.ref.store,row.ref.epoch)
			if err!=.None { return {},false }
			h.claim=v
		case: return {},false
		}
	}
	return h,h.proposal.reference.sequence!=0
}

@(private)
continuous_directory :: proc(prepared: ^PreparedProposal,p: a.MarkerProposal) -> bool {
	return prepared!=nil && prepared.proposal==p && dispatch_directory(prepared,p)==.Eligible
}

@(private)
issue_marker_permit :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,prepared: ^PreparedProposal,
                           decision: a.MarkerApproval,admission,deadline: i64) -> ReviewResult {
	snap,status := intake_snapshot(w,s,root)
	if status!=.Ready { return {status=.Uncertain} }
	h,ok := review_history(snap)
	view := snap.replay.tasks
	if !ok || h.decision!=decision || h.permit!=nil || !a.marker_approval_matches(decision,h.proposal,s.store,s.epoch) ||
	   view[0].approval!=.Approve || view[0].task_version!=h.proposal.expected_task_version ||
	   view[0].control_revision!=h.proposal.expected_control_revision { return {status=.BindingMismatch} }
	if !continuous_directory(prepared,h.proposal) { return {status=.DirectoryHold} }
	start,stamp := client.wb_elapsed_ms(),client.wb_recorded_us()
	if start<admission || stamp<0 { return {status=.Unavailable} }
	grant := LiveGrant{starts={.Task=u64(admission),.Operation=nil,.LockWait=nil,.Capability=u64(start)},prior_ms=u64(start),attempt=h.proposal.attempt}
	v := a.MarkerPermit{reference={s.store,s.epoch,snap.cp.sequence+1},approval=decision.reference,previous_head=snap.cp.head,
	                   recorded_time=u64(stamp),audit_expiry=u64(stamp)+90_000_000,expected_control_revision=view[0].control_revision}
	n,err := l.getrandom(v.capability[:],{})
	m,ee := l.getrandom(v.evidence[:],{})
	if err!=.NONE || n!=16 || ee!=.NONE || m!=16 || v.evidence==decision.evidence || v.evidence==h.task_evidence { return {status=.Unavailable} }
	window := check_window(&grant,client.wb_elapsed_ms())
	if window.result!=.Eligible { return {status=.Withheld} }
	cp,confirmed := store.append_intake(w,s,snap.cp,snap.mark,v,min(window.cutoff,deadline))
	if !confirmed { return {status=.Uncertain} }
	last,ready := intake_snapshot(w,s,root)
	if ready!=.Ready || last.cp!=cp { return {status=.Uncertain} }
	final,valid := review_history(last)
	if !valid || final.permit!=v || last.replay.tasks[0].control_revision!=v.expected_control_revision+1 ||
	   last.replay.tasks[0].consumed || check_window(&grant,client.wb_elapsed_ms()).result!=.Eligible { return {status=.Withheld} }
	grant.permit,grant.capability=v.reference,v.capability
	return {.Permitted,decision.reference,grant}
}

// An exact SQLite tail may finish its historical Confirm. This path has no
// issuing descriptor or elapsed origin and always returns an empty grant.
@(private)
recover_decision :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,snap: IntakeSnapshot,
                         h: ReviewHistory,peer: u32,d: a.MarkerDecision,deadline: i64) -> ReviewResult {
	pledge := snap.pending.(e.Pledge)
	if !client.within_budget(s,2*u64(len(snap.rows))) { return {status=.RecoveryLimitExceeded} }
	cp := e.Checkpoint{s.store,s.epoch,pledge.sequence,pledge.head}
	segments := [?]r.Segment{{rows=snap.rows}}
	candidate := r.project_markers(root,cp,nil,segments[:],snap.receipts[:])
	if candidate.error!=.None || len(candidate.tasks)!=1 { return {status=.ReconciliationRequired} }
	tail := snap.rows[len(snap.rows)-1]
	approval: a.MarkerApproval
	switch tail.bytes[6] {
	case 12:
		v,err := a.decode_marker_approval(tail.bytes,s.store,s.epoch)
		if err!=.None || h.decision!=nil { return {status=.ReconciliationRequired} }
		approval=v
	case 13,14,8:
		if tail.bytes[6]==14 && (h.permit==nil || h.claim!=nil) { return {status=.ReconciliationRequired} }
		if tail.bytes[6]==8 {
			v,err := a.decode_rejection_recorded(tail.bytes,s.store,s.epoch)
			c,claimed := h.claim.(a.MarkerClaim)
			permit,permitted := h.permit.(a.MarkerPermit)
			if !permitted || err!=.None || v.producer!=2 || v.stage!=3 { return {status=.ReconciliationRequired} }
			related := c.reference if claimed else permit.reference
			if v.related!=related { return {status=.ReconciliationRequired} }
		}
		v,exists := h.decision.(a.MarkerApproval)
		if !exists || !a.marker_approval_matches(v,h.proposal,s.store,s.epoch) { return {status=.ReconciliationRequired} }
		approval=v
	case: return {status=.ReconciliationRequired}
	}
	if approval.operator_uid!=u64(peer) || approval.decision!=d { return {status=.DecisionConflict} }
	// A refusal may itself document a missing directory or an occupied leaf.
	// Completing its exact historical receipt confers no directory authority.
	parent,fd := l.Fd(-1),l.Fd(-1)
	defer if parent>=0 { l.close(parent) }
	defer if fd>=0 { l.close(fd) }
	if tail.bytes[6]!=8 {
		err: l.Errno
		parent,err = l.open("attempts",DirectoryFlags)
		if err!=.NONE { return {status=.DirectoryHold} }
		if _,secure := private_dir(parent); !secure { return {status=.DirectoryHold} }
		p := h.proposal
		ok: bool
		fd,ok = attempt_dir(parent,&p,false)
		if !ok { return {status=.DirectoryHold} }
	}
	if !store.confirm_stored(w,s,pledge,nil,deadline,marker=true) { return {status=.Uncertain} }
	return {status=.Recorded,decision=approval.reference}
}

@(private)
review_locked :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,prepared: ^PreparedProposal,display: ^ReviewDisplay,
                      packet: ^DecisionPacket,peer: u32,admission,deadline: i64,inspect_only: bool) -> ReviewResult {
	snap,status := intake_snapshot(w,s,root)
	if inspect_only {
		if (status!=.Ready && status!=.PendingConfirmation) || len(snap.replay.tasks)!=1 || !snap.replay.tasks[0].marker {
			return {status=.ReconciliationRequired}
		}
		display.consumed=snap.replay.tasks[0].consumed
		display.task_version,display.control_revision=snap.replay.tasks[0].task_version,snap.replay.tasks[0].control_revision
		return {status=.Display}
	}
	if status!=.Ready && status!=.PendingConfirmation { return {status=.ReconciliationRequired} }
	h,ok := review_history(snap)
	if !ok { return {status=.ReconciliationRequired} }
	p := h.proposal
	if packet==nil {
		if prepared!=nil && !continuous_directory(prepared,p) { return {status=.DirectoryHold} }
		display^={proposal=p,checkpoint=snap.cp}
		return {status=.Display}
	}
	d := a.MarkerDecision(packet[100])
	expected,valid := decision_packet(p,d)
	if !valid || packet^!=expected || display.proposal!=p { return {status=.BindingMismatch} }
	if status==.PendingConfirmation {
		return recover_decision(w,s,root,snap,h,peer,d,deadline)
	}
	if v,exists := h.decision.(a.MarkerApproval); exists {
		if v.operator_uid!=u64(peer) || v.decision!=d { return {status=.DecisionConflict} }
		return {status=.Recorded,decision=v.reference}
	}
	if display.checkpoint!=snap.cp || snap.replay.tasks[0].task_version!=p.expected_task_version ||
	   snap.replay.tasks[0].control_revision!=p.expected_control_revision { return {status=.BindingMismatch} }
	if !continuous_directory(prepared,p) { return {status=.DirectoryHold} }
	stamp := client.wb_recorded_us()
	if stamp<0 { return {status=.Unavailable} }
	v := a.MarkerApproval{reference={s.store,s.epoch,snap.cp.sequence+1},previous_head=snap.cp.head,recorded_time=u64(stamp),
	                     proposal=p.reference,display_length=p.length,operator_uid=u64(peer),decision=d}
	copy(v.fingerprint[:],packet[32:64])
	copy(v.display_digest[:],packet[68:100])
	n,err := l.getrandom(v.evidence[:],{})
	if err!=.NONE || n!=16 || v.evidence==h.task_evidence { return {status=.Unavailable} }
	_,confirmed := store.append_intake(w,s,snap.cp,snap.mark,v,deadline)
	if !confirmed { return {status=.Uncertain} }
	if d==.Reject { return {status=.Rejected,decision=v.reference} }
	return issue_marker_permit(w,s,root,prepared,v,admission,deadline)
}

// Each call acquires a fresh gate. No writer or custody lock spans the human decision.
@(private)
review_round :: proc(prepared: ^PreparedProposal,display: ^ReviewDisplay,packet: ^DecisionPacket,peer: u32,
                     admission: i64,scratch: ^mem.Arena,inspect_only := false) -> ReviewResult {
	temp := mem.begin_arena_temp_memory(scratch)
	defer mem.end_arena_temp_memory(temp)
	context.allocator=mem.arena_allocator(scratch)
	root,cust,trusted := intake_configuration()
	if !trusted || cust==peer || !store.limit_sqlite() { return {status=.Unavailable} }
	start := client.wb_elapsed_ms()
	if start<admission || start>=admission+180_000 { return {status=.Withheld} }
	s := client.Session{path="endpoints/runtime.sock",uid=cust,store=root.store,epoch=1,deadline=start+60_000}
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return {status=.LockUnavailable} }
	defer client.wb_release_gate(gate)
	locked := client.wb_elapsed_ms()
	if locked<start || locked-start>=5_000 { return {status=.LockUnavailable} }
	registered: u32
	if client.wb_approval_roles(1,&registered)!=0 || registered!=peer { return {status=.Withheld} }
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return {status=.Unavailable} }
	result := ReviewResult{status=.Unavailable}
	if store.limit_writer_cache(w) {
		result=review_locked(w,&s,root,prepared,display,packet,peer,admission,min(start+30_000,admission+180_000),inspect_only)
	}
	if !store.close_writer(&w) { return {status=.Uncertain} }
	if s.exhausted { return {status=.RecoveryLimitExceeded} }
	return result
}

// The receipt service reports the confirmed versions even when outstanding receipts block a new decision.
marker_review_versions :: proc(operator: u32,admission: i64,scratch: ^mem.Arena) -> (u64,u64,bool,bool) {
	display: ReviewDisplay
	result := review_round(nil,&display,nil,operator,admission,scratch,inspect_only=true)
	return display.task_version,display.control_revision,display.consumed,result.status==.Display
}

marker_review :: proc(fd: i32,operator: u32,prepared: ^PreparedProposal,admission: i64,scratch: ^mem.Arena) -> ReviewResult {
	peer: u32
	if client.wb_approval_peer(fd,operator,&peer)!=0 { return {status=.Withheld} }
	deadline := admission+180_000
	display: ReviewDisplay
	result := review_round(prepared,&display,nil,peer,admission,scratch)
	if result.status!=.Display { return result }
	p := &display.proposal
	wire,err := a.encode_marker_proposal(p^,p.reference.store,p.reference.epoch)
	if err!=.None || client.wb_approval_packet(fd,&wire.data,i32(wire.length),1,deadline)!=i32(wire.length) { return {status=.Unavailable} }
	packet: DecisionPacket
	if client.wb_approval_packet(fd,&packet,len(packet),0,deadline)!=len(packet) { return {status=.Withheld} }
	result=review_round(prepared,&display,&packet,peer,admission,scratch)
	b: [33]u8
	b[0]=u8(result.status)
	copy(b[1:17],result.decision.store[:])
	endian.put_u64(b[17:25],.Little,u64(result.decision.epoch))
	endian.put_u64(b[25:],.Little,u64(result.decision.sequence))
	// A lost reply leaves the confirmed decision available to an exact receipt lookup.
	_=client.wb_approval_packet(fd,&b,len(b),1,deadline)
	return result
}
