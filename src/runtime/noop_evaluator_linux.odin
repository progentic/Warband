package reconcile

import "core:crypto/sha2"
import a "../audit"
import e "../domain/events"
import store "../store"
import client "client"

// The only evidence input is a reference. Load the observation in a newly
// validated snapshot and compare the wire bytes against the runtime criterion.
@(private)
evaluate_confirmed :: proc(w: store.VerifiedWriter,s: ^client.Session,requested,ref: e.EventRef) -> GateResult {
	page, ready := client.verify(s,0)
	if !ready || page.pending != nil { return .Unavailable }
	cp := page.committed
	h, ok := store.noop_history(w,cp,s)
	if !ok || !bound_claim(h,requested) { return .EvidenceInvalid }
	raw := h.observation_bytes
	obs, err := a.decode_observation_recorded(raw[:],cp.store,cp.epoch)
	if err != .None || obs.reference != ref || obs.claim != h.claim.(a.DispatchClaimed).reference { return .EvidenceInvalid }

	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	domain: string = a.EventDomain
	sha2.update(&ctx,transmute([]u8)domain)
	sha2.update(&ctx,raw[:a.ObservationRecordedBodySize])
	digest: [32]u8
	sha2.final(&ctx,digest[:])
	if digest != h.observation_digest { return .EvidenceInvalid }
	verdict := a.EvaluationVerdict.Rejected
	result := GateResult.EvaluationRejected
	if obs.outcome == .Returned && string(raw[107:111]) == "NOOP" {
		verdict, result = .Verified, .EvaluationVerified
	}
	if prior, exists := h.evaluation.(a.EvaluationRecorded); exists {
		if prior.observation != ref || prior.claim != obs.claim || prior.observed_event_digest != digest ||
		   prior.verdict != verdict { return .EvidenceInvalid }
		return result
	}
	id, fresh := new_evidence(h)
	stamp := client.wb_recorded_us()
	if !fresh || stamp < 0 { return .Unavailable }
	evaluation := a.EvaluationRecorded{reference={cp.store,cp.epoch,cp.sequence+1},previous_head=cp.head,
		recorded_time=u64(stamp),observation=ref,claim=obs.claim,observed_event_digest=digest,verdict=verdict,evidence=id}
	_, confirmed := store.append_noop(w,s,cp,h.mark,evaluation,s.deadline)
	if !confirmed { return .Unavailable }
	return result
}
