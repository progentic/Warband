package audit

import "../domain/events"
import "core:encoding/endian"

ObservationOutcome :: enum u8 {Returned = 1, Indeterminate = 2}
ObservationRecorded :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	claim: events.EventRef,
	evidence: events.EvidenceId,
	outcome: ObservationOutcome,
	previous_head: [32]u8,
}
ObservationRecordedBytes :: [143]u8
ObservationRecordedBodySize :: 111

encode_observation_recorded :: proc(value: ObservationRecorded, store: events.StoreId, epoch: events.Epoch) -> (ObservationRecordedBytes, Error) {
	value := value
	if err := validate_observation_recorded(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: ObservationRecordedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 5, 3)
	copy(bytes[56:72], value.claim.store[:])
	assert(endian.put_u64(bytes[72:80], .Little, u64(value.claim.epoch)))
	assert(endian.put_u64(bytes[80:88], .Little, u64(value.claim.sequence)))
	copy(bytes[88:104], value.evidence[:])
	bytes[104] = u8(value.outcome)
	assert(endian.put_u16(bytes[105:107], .Little, 1))
	observed := observation_bytes(value.outcome)
	copy(bytes[107:111], observed[:])
	return bytes, .None
}

decode_observation_recorded :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (ObservationRecorded, Error) {
	envelope, err := read_envelope(bytes, 5, 3, 55)
	if err != .None {
		return {}, err
	}
	criterion, _ := endian.get_u16(bytes[105:107], .Little)
	if bytes[104] < 1 || bytes[104] > 2 || criterion != 1 {
		return {}, .Unsupported
	}
	outcome := ObservationOutcome(bytes[104])
	observed := observation_bytes(outcome)
	if string(bytes[107:111]) != string(observed[:]) {
		return {}, .Malformed
	}
	value := ObservationRecorded{reference = envelope.reference, recorded_time = envelope.recorded_time, previous_head = envelope.previous_head, outcome = outcome}
	copy(value.claim.store[:], bytes[56:72])
	claim_epoch, _ := endian.get_u64(bytes[72:80], .Little)
	claim_sequence, _ := endian.get_u64(bytes[80:88], .Little)
	value.claim.epoch = events.Epoch(claim_epoch)
	value.claim.sequence = events.Sequence(claim_sequence)
	copy(value.evidence[:], bytes[88:104])
	if validation_error := validate_observation_recorded(value, store, epoch); validation_error != .None {
		return {}, validation_error
	}
	return value, .None
}

digest_observation_recorded :: proc(value: ObservationRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_observation_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:ObservationRecordedBodySize]), .None
}

@(private)
observation_bytes :: proc(outcome: ObservationOutcome) -> [4]u8 {
	if outcome == .Returned {
		return {'N', 'O', 'O', 'P'}
	}
	return {}
}

@(private)
validate_observation_recorded :: proc(value: ObservationRecorded, store: events.StoreId, epoch: events.Epoch) -> Error {
	if value.outcome != .Returned && value.outcome != .Indeterminate {
		return .Unsupported
	}
	if events.validate_event_ref(value.reference, store, epoch) != .None || events.validate_event_ref(value.claim, store, epoch) != .None {
		return .InvalidIdentity
	}
	empty_evidence := events.EvidenceId{}
	if value.evidence == empty_evidence {
		return .InvalidIdentity
	}
	if value.claim.sequence >= value.reference.sequence {
		return .Malformed
	}
	return .None
}
