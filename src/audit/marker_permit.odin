package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerPermit :: struct {
	reference, approval: e.EventRef,
	recorded_time, expected_control_revision, audit_expiry: u64,
	capability: e.CapabilityId,
	evidence: e.EvidenceId,
	previous_head: [32]u8,
}
MarkerPermitBytes :: [169]u8

// A wire Ref identifies a position. The confirmed history supplies its role.
@(private)
validate_marker_predecessor :: proc(ref, prior: e.EventRef, store: e.StoreId, epoch: e.Epoch) -> Error {
	if e.validate_event_ref(ref,store,epoch) != .None || e.validate_event_ref(prior,store,epoch) != .None {
		return .InvalidIdentity
	}
	if prior.sequence >= ref.sequence { return .Malformed }
	return .None
}

@(private)
validate_marker_permit :: proc(v: MarkerPermit, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.evidence == (e.EvidenceId{}) || v.capability == (e.CapabilityId{}) { return .InvalidIdentity }
	if v.expected_control_revision == max(u64) { return .Malformed }
	return validate_marker_predecessor(v.reference,v.approval,store,epoch)
}

encode_marker_permit :: proc(v: MarkerPermit, store: e.StoreId, epoch: e.Epoch) -> (MarkerPermitBytes, Error) {
	if err := validate_marker_permit(v,store,epoch); err != .None { return {},err }
	v := v
	b: MarkerPermitBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},13,2,2)
	write_ref(b[56:88],v.approval)
	copy(b[88:104],v.capability[:])
	assert(endian.put_u64(b[104:112],.Little,v.expected_control_revision))
	assert(endian.put_u64(b[112:120],.Little,v.audit_expiry))
	b[120] = 1
	copy(b[121:137],v.evidence[:])
	return b,.None
}

decode_marker_permit :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerPermit, Error) {
	env,err := read_envelope(b,13,2,81,2)
	if err != .None { return {},err }
	if b[120] != 1 { return {},.Malformed }
	v := MarkerPermit{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,approval=read_ref(b[56:88])}
	copy(v.capability[:],b[88:104])
	v.expected_control_revision,_ = endian.get_u64(b[104:112],.Little)
	v.audit_expiry,_ = endian.get_u64(b[112:120],.Little)
	copy(v.evidence[:],b[121:137])
	if invalid := validate_marker_permit(v,store,epoch); invalid != .None { return {},invalid }
	return v,.None
}

digest_marker_permit :: proc(v: MarkerPermit, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_permit(v,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}
