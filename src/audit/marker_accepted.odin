package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerAccepted :: struct {
	reference, evaluation, claim: e.EventRef,
	recorded_time: u64,
	transition: e.TransitionId,
	expected_task_version, expected_control_revision: u64,
	previous_head: [32]u8,
}
MarkerAcceptedBytes :: [193]u8

@(private)
validate_marker_accepted :: proc(v: MarkerAccepted, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.transition == (e.TransitionId{}) { return .InvalidIdentity }
	if v.expected_task_version == 0 || v.expected_task_version == max(u64) ||
	   v.expected_control_revision < 2 || v.expected_control_revision == max(u64) { return .Malformed }
	return validate_reference_chain(v.reference,v.evaluation,v.claim,store,epoch)
}

encode_marker_accepted :: proc(v: MarkerAccepted, store: e.StoreId, epoch: e.Epoch) -> (MarkerAcceptedBytes, Error) {
	if err := validate_marker_accepted(v,store,epoch); err != .None { return {},err }
	v := v
	b: MarkerAcceptedBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},17,5,2)
	write_ref(b[56:88],v.evaluation)
	write_ref(b[88:120],v.claim)
	copy(b[120:136],v.transition[:])
	assert(endian.put_u64(b[136:144],.Little,v.expected_task_version))
	assert(endian.put_u64(b[144:152],.Little,v.expected_control_revision))
	assert(endian.put_u64(b[152:160],.Little,v.expected_task_version+1))
	b[160] = 2
	return b,.None
}

decode_marker_accepted :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerAccepted, Error) {
	env,err := read_envelope(b,17,5,105,2)
	if err != .None { return {},err }
	if b[160] != 2 { return {},.Unsupported }
	v := MarkerAccepted{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                    evaluation=read_ref(b[56:88]),claim=read_ref(b[88:120])}
	copy(v.transition[:],b[120:136])
	v.expected_task_version,_ = endian.get_u64(b[136:144],.Little)
	v.expected_control_revision,_ = endian.get_u64(b[144:152],.Little)
	if invalid := validate_marker_accepted(v,store,epoch); invalid != .None { return {},invalid }
	next,_ := endian.get_u64(b[152:160],.Little)
	if next != v.expected_task_version+1 { return {},.Malformed }
	return v,.None
}

digest_marker_accepted :: proc(v: MarkerAccepted, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_accepted(v,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}
