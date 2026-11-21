package reconcile

import "core:crypto/sha2"
import "core:fmt"
import "core:sys/linux"
import a "../audit"
import e "../domain/events"
import t "../domain/timing"
import store "../store"
import client "client"

GateResult :: enum {EvidenceInvalid, Unavailable, ReconciliationRequired, MissingClaim, NoLiveGrantEntry,
                    ExpiredCapability, InvalidClock, TaskDeadlineExceeded, RefusalUnconfirmed, Eligible, Dispatched}

@(private)
PROOF :: #config(WARBAND_TEST_CLAIM_BARRIER,false)

@(private)
LiveGrant :: struct {
	starts: t.Starts,
	prior_ms: u64,
	permit: e.EventRef,
	capability: e.CapabilityId,
	claim: e.EventRef,
	attempt: e.AttemptId,
}

@(private)
Window :: struct {result: GateResult, cutoff: i64, observed: i64}

@(private)
check_window :: proc(grant: ^LiveGrant, now: i64) -> Window {
	if now < 0 { return {result=.InvalidClock} }
	decision := t.check(.Capability,grant.starts,grant.prior_ms,u64(now))
	#partial switch decision.outcome {
	case .ExpiredCapability: return {result=.ExpiredCapability,observed=now}
	case .TaskDeadlineExceeded: return {result=.TaskDeadlineExceeded,observed=now}
	case .WithinDeadline:
		grant.prior_ms = u64(now)
		if decision.remaining_ms > u64(max(i64)-now) { return {result=.InvalidClock} }
		return {.Eligible,now+i64(decision.remaining_ms),now}
	case: return {result=.InvalidClock,observed=now}
	}
}

@(private)
valid_proposal :: proc(task: a.TaskCreated, proposal: a.ProposalRecorded) -> bool {
	task := task
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	domain: string = "warband.task.v1\x00"
	sha2.update(&ctx,transmute([]u8)domain)
	sha2.update(&ctx,task.task[:])
	sha2.update(&ctx,task.run[:])
	sha2.update(&ctx,task.command[:])
	digest: [32]u8
	sha2.final(&ctx,digest[:])
	return task.input_digest == digest && task.reference.sequence < proposal.reference.sequence &&
	       task.task == proposal.task && task.run == proposal.run && proposal.expected_task_version == 1 &&
	       proposal.policy_version == 1 && !proposal.approval_required
}

@(private)
issue_and_claim :: proc(w: store.VerifiedWriter, s: ^client.Session, cp: e.Checkpoint, mark: u64,
                        proposal: a.ProposalRecorded, task_evidence: e.EvidenceId, admission: i64, live: ^Maybe(LiveGrant)) -> GateResult {
	start := client.wb_elapsed_ms()
	stamp := client.wb_recorded_us()
	if start < admission || stamp < 0 { return .InvalidClock }
	grant := LiveGrant{starts={.Task=u64(admission),.Operation=nil,.LockWait=nil,.Capability=u64(start)},prior_ms=u64(start)}
	// Separate random identifiers for the grant, evidence and attempt. Never accept IDs from the caller.
	ids: [48]u8
	count, err := linux.getrandom(ids[:],{})
	if err != .NONE || count != len(ids) { return .Unavailable }
	auth := a.AuthorizationRecorded{reference={cp.store,cp.epoch,cp.sequence+1},previous_head=cp.head,
		recorded_time=u64(stamp),proposal=proposal.reference,decision=.Permit,use_limit=1,expiry=u64(stamp)+90_000_000}
	copy(auth.capability[:],ids[:16])
	copy(auth.evidence[:],ids[16:32])
	if auth.evidence == task_evidence { return .Unavailable }
	copy(grant.attempt[:],ids[32:])
	window := check_window(&grant,client.wb_elapsed_ms())
	if window.result != .Eligible { return window.result }
	auth_head, ok := store.append_noop(w,s,cp,mark,auth,window.cutoff)
	if !ok { return .Unavailable }
	grant.permit,grant.capability = auth.reference,auth.capability
	fingerprint, fp_err := a.fingerprint_proposal(proposal,cp.store,cp.epoch)
	stamp = client.wb_recorded_us()
	if fp_err != .None || stamp < 0 { return .Unavailable }
	claim := a.DispatchClaimed{reference={cp.store,cp.epoch,auth_head.sequence+1},previous_head=auth_head.head,
		recorded_time=u64(stamp),claim_time=u64(stamp),authorization=auth.reference,capability=auth.capability,
		attempt=grant.attempt,expected_task_version=1,expected_control_revision=1,proposal_fingerprint=fingerprint}
	window = check_window(&grant,client.wb_elapsed_ms())
	if window.result != .Eligible { return window.result }
	_, ok = store.append_noop(w,s,auth_head,mark,claim,window.cutoff)
	if !ok { return .Unavailable }
	window = check_window(&grant,client.wb_elapsed_ms()) // receipt has arrived; enforce a fresh observation at confirmation
	if window.result != .Eligible { return window.result }
	grant.claim = claim.reference
	live^ = grant
	when PROOF {
		fmt.println("authorization_start_ms",start,"claim_confirmed_ms",window.observed)
		if linux.kill(linux.getpid(),.SIGSTOP) != .NONE { return .Unavailable }
	}
	return .Eligible
}

@(private)
invoke_noop :: proc() -> [4]u8 {
	when PROOF { fmt.println("primitive_invoked") }
	return {'N','O','O','P'}
}

@(private)
dispatch :: proc(w: store.VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,h: store.NoopHistory,
                 task: a.TaskCreated, proposal: a.ProposalRecorded,live: ^Maybe(LiveGrant)) -> GateResult {
	auth, permitted := h.permit.(a.AuthorizationRecorded)
	claim, claimed := h.claim.(a.DispatchClaimed)
	if !claimed { return .MissingClaim }
	fp, err := a.fingerprint_proposal(proposal,cp.store,cp.epoch)
	if !valid_proposal(task,proposal) || !permitted || auth.decision != .Permit || auth.use_limit != 1 ||
	   auth.proposal != proposal.reference || auth.expected_control_revision != 0 ||
	   claim.authorization != auth.reference || claim.capability != auth.capability ||
	   claim.expected_task_version != 1 || claim.expected_control_revision != 1 ||
	   err != .None || claim.proposal_fingerprint != fp { return .EvidenceInvalid }

	when PROOF { fmt.println("confirmed_evidence", u64(auth.reference.sequence), u64(claim.reference.sequence)) }
	result := GateResult.NoLiveGrantEntry
	grant, present := live^.(LiveGrant)
	tick := client.wb_elapsed_ms()
	if tick < 0 { return .InvalidClock }
	if present {
		if grant.permit != auth.reference || grant.claim != claim.reference || grant.attempt != claim.attempt ||
		   grant.capability != claim.capability { return .EvidenceInvalid }
		window := check_window(&grant,tick)
		tick, result = window.observed, window.result
		if result == .Eligible {
			live^ = nil
			value := invoke_noop()
			when PROOF { fmt.println("dispatch_ms",tick) }
			fmt.println("returned",string(value[:]))
			return .Dispatched
		}
	}
	when PROOF { fmt.println("dispatch_ms",tick,"refusal",result) }
	wire, encode_err := a.encode_dispatch_claimed(claim,cp.store,cp.epoch)
	stamp := client.wb_recorded_us()
	if stamp < 0 || encode_err != .None { return .RefusalUnconfirmed }
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx,wire[:])
	rejection := a.RejectionRecorded{reference={cp.store,cp.epoch,cp.sequence+1},recorded_time=u64(stamp),
		previous_head=cp.head,producer=2,stage=3,reason=9,related=claim.reference}
	if result == .ExpiredCapability { rejection.reason = 5 }
	sha2.final(&ctx,rejection.rejected_input_digest[:])
	_, ok := store.append_noop(w,s,cp,h.mark,rejection,s.deadline)
	if !ok { return .RefusalUnconfirmed }
	return result
}

run_noop_gate :: proc(path: cstring,s: ^client.Session,archives: []Archive,requested: e.EventRef) -> (result: GateResult) {
	admission := client.wb_elapsed_ms()
	if admission < 0 || !store.limit_sqlite() { return .Unavailable }
	fd := client.wb_writer_gate(path)
	if fd < 0 { return .Unavailable }
	defer client.wb_release_gate(fd)
	locked := client.wb_elapsed_ms()
	if locked < admission || locked-admission >= 5_000 { return .Unavailable }
	w, open_err := store.open_writer(path)
	if open_err != .None { return .Unavailable }
	defer if !store.close_writer(&w) { result = .Unavailable }
	if !store.limit_writer_cache(w) { return .Unavailable }
	live: Maybe(LiveGrant) // Starts empty in each execution. Replay cannot write this slot.
	for {
		now := client.wb_elapsed_ms()
		if now < admission { return .InvalidClock }
		s.deadline, s.visits, s.exhausted = now+60_000,0,false
		compared: e.EventRef
		recovery := reconcile_locked(w,s,archives,nil,&compared)
		if recovery != .Ready && recovery != .PendingConfirmation { return .ReconciliationRequired }
		page, ok := client.verify(s,0)
		if !ok || page.pending != nil { return .Unavailable }
		h, valid := store.noop_history(w,page.committed,s)
		task, created := h.task.(a.TaskCreated)
		proposal, proposed := h.proposal.(a.ProposalRecorded)
		if !valid || !created || !proposed || proposal.reference != requested || !valid_proposal(task,proposal) { return .EvidenceInvalid }
		if h.permit == nil && h.claim == nil && live == nil {
			issued := issue_and_claim(w,s,page.committed,h.mark,proposal,task.evidence,admission,&live)
			if issued != .Eligible { return issued }
			continue // reconcile the pre-dispatch receipt snapshot and read durable evidence again
		}
		return dispatch(w,s,page.committed,h,task,proposal,&live)
	}
}
