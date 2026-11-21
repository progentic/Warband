package state

import a "../audit"
import e "../domain/events"
import "core:crypto/sha2"

Evidence :: struct {
	task: Maybe(a.TaskCreated),
	proposal: Maybe(a.ProposalRecorded),
	permit: Maybe(a.AuthorizationRecorded),
	claim: Maybe(a.DispatchClaimed),
	observation: Maybe(a.ObservationRecorded),
	observation_bytes: a.ObservationRecordedBytes,
	observation_digest: [32]u8,
	evaluation: Maybe(a.EvaluationRecorded),
	transition: Maybe(a.TransitionAccepted),
	task_version, control_revision: u64,
	revoked, terminal: bool,
}

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

bound_claim :: proc(h: Evidence, requested: e.EventRef) -> bool {
	task, created := h.task.(a.TaskCreated)
	proposal, proposed := h.proposal.(a.ProposalRecorded)
	auth, permitted := h.permit.(a.AuthorizationRecorded)
	claim, claimed := h.claim.(a.DispatchClaimed)
	if !created || !proposed || !permitted || !claimed || proposal.reference != requested { return false }
	fp, err := a.fingerprint_proposal(proposal,requested.store,requested.epoch)
	return valid_proposal(task,proposal) && auth.decision == .Permit && auth.use_limit == 1 &&
	       auth.proposal == requested && auth.expected_control_revision == 0 &&
	       claim.authorization == auth.reference && claim.capability == auth.capability &&
	       claim.expected_task_version == 1 && claim.expected_control_revision == 1 &&
	       err == .None && claim.proposal_fingerprint == fp
}

Decision :: enum {InvalidEvidence, RejectedEvaluation, Revoked, Terminal, StaleVersions, Eligible, Recorded}

decide :: proc(h: Evidence, requested: e.EventRef, task_version, control_revision: u64) -> Decision {
	h := h
	proposal, proposed := h.proposal.(a.ProposalRecorded)
	obs, observed := h.observation.(a.ObservationRecorded)
	ev, evaluated := h.evaluation.(a.EvaluationRecorded)
	if !proposed || !observed || !evaluated || !bound_claim(h,proposal.reference) { return .InvalidEvidence }
	claim := h.claim.(a.DispatchClaimed)
	if ev.reference != requested || ev.observation != obs.reference || ev.claim != claim.reference ||
	   obs.claim != claim.reference || ev.observed_event_digest != h.observation_digest { return .InvalidEvidence }
	if ev.verdict != .Verified || obs.outcome != .Returned || string(h.observation_bytes[107:111]) != "NOOP" { return .RejectedEvaluation }
	// A stored acceptance was checked at its original position in the confirmed prefix.
	if prior, exists := h.transition.(a.TransitionAccepted); exists {
		if prior.evaluation != requested || prior.claim != claim.reference { return .InvalidEvidence }
		if prior.expected_task_version != task_version || prior.expected_control_revision != control_revision { return .StaleVersions }
		return .Recorded
	}
	if h.revoked { return .Revoked }
	if h.terminal { return .Terminal }
	if h.task_version != task_version || h.control_revision != control_revision { return .StaleVersions }
	return .Eligible
}
