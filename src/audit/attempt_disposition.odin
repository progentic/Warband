package audit

import "../domain/events"
import "core:encoding/endian"

Disposition :: enum u8 {Indeterminate = 1, RejectStop = 2}

AttemptDisposition :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	claim: events.EventRef,
	disposition: Disposition,
	expected_control_revision: u64,
	reason: u16,
	previous_head: [32]u8,
}
AttemptDispositionBytes :: [131]u8
AttemptDispositionBodySize :: 99

@(private)
validate_attempt_disposition :: proc(value: AttemptDisposition, store: events.StoreId, epoch: events.Epoch) -> Error {
	if events.validate_event_ref(value.reference, store, epoch) != .None || events.validate_event_ref(value.claim, store, epoch) != .None {
		return .InvalidIdentity
	}
	if value.claim.sequence >= value.reference.sequence {
		return .Malformed
	}
	if value.disposition != .Indeterminate && value.disposition != .RejectStop {
		return .Unsupported
	}
	if value.reason < 1 || value.reason > 13 {
		return .Unsupported
	}
	return .None
}

encode_attempt_disposition :: proc(value: AttemptDisposition, store: events.StoreId, epoch: events.Epoch) -> (AttemptDispositionBytes, Error) {
	value := value
	if err := validate_attempt_disposition(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: AttemptDispositionBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 10, 5)
	write_ref(bytes[56:88], value.claim)
	bytes[96] = u8(value.disposition)
	assert(endian.put_u64(bytes[88:96], .Little, value.expected_control_revision))
	assert(endian.put_u16(bytes[97:99], .Little, value.reason))
	return bytes, .None
}

decode_attempt_disposition :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (AttemptDisposition, Error) {
	env, err := read_envelope(bytes, 10, 5, 43)
	if err != .None {
		return {}, err
	}
	value := AttemptDisposition{reference = env.reference, recorded_time = env.recorded_time, previous_head = env.previous_head, claim = read_ref(bytes[56:88])}
	value.disposition = Disposition(bytes[96])
	value.expected_control_revision, _ = endian.get_u64(bytes[88:96], .Little)
	value.reason, _ = endian.get_u16(bytes[97:99], .Little)
	if err = validate_attempt_disposition(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

digest_attempt_disposition :: proc(value: AttemptDisposition, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_attempt_disposition(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:AttemptDispositionBodySize]), .None
}
