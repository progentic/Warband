package audit

import "../domain/events"
import "core:encoding/endian"

DispatchClaimed :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	authorization: events.EventRef,
	attempt: events.AttemptId,
	capability: events.CapabilityId,
	expected_task_version: u64,
	expected_control_revision: u64,
	proposal_fingerprint: [32]u8,
	claim_time: u64,
	previous_head: [32]u8,
}
DispatchClaimedBytes :: [208]u8
DispatchClaimedBodySize :: 176

encode_dispatch_claimed :: proc(value: DispatchClaimed, store: events.StoreId, epoch: events.Epoch) -> (DispatchClaimedBytes, Error) {
	value := value
	if err := validate_dispatch_claimed(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: DispatchClaimedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 4, 2)
	copy(bytes[56:72], value.authorization.store[:])
	assert(endian.put_u64(bytes[72:80], .Little, u64(value.authorization.epoch)))
	assert(endian.put_u64(bytes[80:88], .Little, u64(value.authorization.sequence)))
	copy(bytes[88:104], value.attempt[:])
	copy(bytes[104:120], value.capability[:])
	assert(endian.put_u64(bytes[120:128], .Little, value.expected_task_version))
	assert(endian.put_u64(bytes[128:136], .Little, value.expected_control_revision))
	copy(bytes[136:168], value.proposal_fingerprint[:])
	assert(endian.put_u64(bytes[168:176], .Little, value.claim_time))
	return bytes, .None
}

decode_dispatch_claimed :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (DispatchClaimed, Error) {
	envelope, err := read_envelope(bytes, 4, 2, 120)
	if err != .None {
		return {}, err
	}
	value := DispatchClaimed{reference = envelope.reference, recorded_time = envelope.recorded_time, previous_head = envelope.previous_head}
	copy(value.authorization.store[:], bytes[56:72])
	authorization_epoch, _ := endian.get_u64(bytes[72:80], .Little)
	authorization_sequence, _ := endian.get_u64(bytes[80:88], .Little)
	value.authorization.epoch = events.Epoch(authorization_epoch)
	value.authorization.sequence = events.Sequence(authorization_sequence)
	copy(value.attempt[:], bytes[88:104])
	copy(value.capability[:], bytes[104:120])
	value.expected_task_version, _ = endian.get_u64(bytes[120:128], .Little)
	value.expected_control_revision, _ = endian.get_u64(bytes[128:136], .Little)
	copy(value.proposal_fingerprint[:], bytes[136:168])
	value.claim_time, _ = endian.get_u64(bytes[168:176], .Little)
	if validation_error := validate_dispatch_claimed(value, store, epoch); validation_error != .None {
		return {}, validation_error
	}
	return value, .None
}

digest_dispatch_claimed :: proc(value: DispatchClaimed, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_dispatch_claimed(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:DispatchClaimedBodySize]), .None
}

@(private)
validate_dispatch_claimed :: proc(value: DispatchClaimed, store: events.StoreId, epoch: events.Epoch) -> Error {
	if events.validate_event_ref(value.reference, store, epoch) != .None || events.validate_event_ref(value.authorization, store, epoch) != .None {
		return .InvalidIdentity
	}
	empty_attempt := events.AttemptId{}
	empty_capability := events.CapabilityId{}
	if value.attempt == empty_attempt || value.capability == empty_capability {
		return .InvalidIdentity
	}
	if value.authorization.sequence >= value.reference.sequence || value.expected_task_version == 0 {
		return .Malformed
	}
	return .None
}
