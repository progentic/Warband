package audit

import "../domain/events"
import "core:encoding/endian"

CapabilityRevoked :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	authorization: events.EventRef,
	capability: events.CapabilityId,
	expected_control_revision: u64,
	reason: u16,
	previous_head: [32]u8,
}
CapabilityRevokedBytes :: [146]u8
CapabilityRevokedBodySize :: 114

@(private)
validate_capability_revoked :: proc(value: CapabilityRevoked, store: events.StoreId, epoch: events.Epoch) -> Error {
	if events.validate_event_ref(value.reference, store, epoch) != .None || events.validate_event_ref(value.authorization, store, epoch) != .None {
		return .InvalidIdentity
	}
	if value.authorization.sequence >= value.reference.sequence {
		return .Malformed
	}
	empty := events.CapabilityId{}
	if value.capability == empty {
		return .InvalidIdentity
	}
	if value.reason < 1 || value.reason > 13 {
		return .Unsupported
	}
	return .None
}

encode_capability_revoked :: proc(value: CapabilityRevoked, store: events.StoreId, epoch: events.Epoch) -> (CapabilityRevokedBytes, Error) {
	value := value
	if err := validate_capability_revoked(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: CapabilityRevokedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 9, 2)
	write_ref(bytes[56:88], value.authorization)
	copy(bytes[88:104], value.capability[:])
	assert(endian.put_u64(bytes[104:112], .Little, value.expected_control_revision))
	assert(endian.put_u16(bytes[112:114], .Little, value.reason))
	return bytes, .None
}

decode_capability_revoked :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (CapabilityRevoked, Error) {
	env, err := read_envelope(bytes, 9, 2, 58)
	if err != .None {
		return {}, err
	}
	value := CapabilityRevoked{reference = env.reference, recorded_time = env.recorded_time, previous_head = env.previous_head, authorization = read_ref(bytes[56:88])}
	copy(value.capability[:], bytes[88:104])
	value.expected_control_revision, _ = endian.get_u64(bytes[104:112], .Little)
	value.reason, _ = endian.get_u16(bytes[112:114], .Little)
	if err = validate_capability_revoked(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

digest_capability_revoked :: proc(value: CapabilityRevoked, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_capability_revoked(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:CapabilityRevokedBodySize]), .None
}
