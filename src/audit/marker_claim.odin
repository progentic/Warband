package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerClaim :: struct {
	reference, permit: e.EventRef,
	recorded_time, expected_task_version, expected_control_revision: u64,
	attempt: e.AttemptId,
	capability: e.CapabilityId,
	fingerprint, previous_head: [32]u8,
}
MarkerClaimBytes :: [200]u8

@(private)
validate_marker_claim :: proc(v: MarkerClaim, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.attempt == (e.AttemptId{}) || v.capability == (e.CapabilityId{}) { return .InvalidIdentity }
	if v.expected_task_version == 0 || v.expected_control_revision == 0 || v.expected_control_revision == max(u64) {
		return .Malformed
	}
	return validate_marker_predecessor(v.reference,v.permit,store,epoch)
}

encode_marker_claim :: proc(v: MarkerClaim, store: e.StoreId, epoch: e.Epoch) -> (MarkerClaimBytes, Error) {
	if err := validate_marker_claim(v,store,epoch); err != .None { return {},err }
	v := v
	b: MarkerClaimBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},14,2,2)
	write_ref(b[56:88],v.permit)
	copy(b[88:104],v.attempt[:])
	copy(b[104:120],v.capability[:])
	assert(endian.put_u64(b[120:128],.Little,v.expected_task_version))
	assert(endian.put_u64(b[128:136],.Little,v.expected_control_revision))
	copy(b[136:168],v.fingerprint[:])
	return b,.None
}

decode_marker_claim :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerClaim, Error) {
	env,err := read_envelope(b,14,2,112,2)
	if err != .None { return {},err }
	v := MarkerClaim{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,permit=read_ref(b[56:88])}
	copy(v.attempt[:],b[88:104])
	copy(v.capability[:],b[104:120])
	v.expected_task_version,_ = endian.get_u64(b[120:128],.Little)
	v.expected_control_revision,_ = endian.get_u64(b[128:136],.Little)
	copy(v.fingerprint[:],b[136:168])
	if invalid := validate_marker_claim(v,store,epoch); invalid != .None { return {},invalid }
	return v,.None
}

digest_marker_claim :: proc(v: MarkerClaim, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_claim(v,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}
