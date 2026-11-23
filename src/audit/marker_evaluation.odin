package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerVerdict :: enum u8 {Verified=1, Incomplete, OperatorReconciliation}
MarkerEvaluation :: struct {
	reference, observation, claim: e.EventRef,
	recorded_time: u64,
	observation_digest: [32]u8,
	verdict: MarkerVerdict,
	evidence: e.EvidenceId,
	previous_head: [32]u8,
}
MarkerEvaluationBytes :: [203]u8

@(private)
validate_marker_evaluation :: proc(v: MarkerEvaluation, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.evidence == (e.EvidenceId{}) { return .InvalidIdentity }
	if v.verdict < .Verified || v.verdict > .OperatorReconciliation { return .Unsupported }
	return validate_reference_chain(v.reference,v.observation,v.claim,store,epoch)
}

encode_marker_evaluation :: proc(v: MarkerEvaluation, store: e.StoreId, epoch: e.Epoch) -> (MarkerEvaluationBytes, Error) {
	if err := validate_marker_evaluation(v,store,epoch); err != .None { return {},err }
	v := v
	b: MarkerEvaluationBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},16,8,2)
	write_ref(b[56:88],v.observation)
	write_ref(b[88:120],v.claim)
	copy(b[120:152],v.observation_digest[:])
	assert(endian.put_u16(b[152:154],.Little,2))
	b[154] = u8(v.verdict)
	copy(b[155:171],v.evidence[:])
	return b,.None
}

decode_marker_evaluation :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerEvaluation, Error) {
	env,err := read_envelope(b,16,8,115,2)
	if err != .None { return {},err }
	criterion,_ := endian.get_u16(b[152:154],.Little)
	if criterion != 2 { return {},.Unsupported }
	v := MarkerEvaluation{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                      observation=read_ref(b[56:88]),claim=read_ref(b[88:120]),verdict=MarkerVerdict(b[154])}
	copy(v.observation_digest[:],b[120:152])
	copy(v.evidence[:],b[155:171])
	if invalid := validate_marker_evaluation(v,store,epoch); invalid != .None { return {},invalid }
	return v,.None
}

digest_marker_evaluation :: proc(v: MarkerEvaluation, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_evaluation(v,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}
