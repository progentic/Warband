package audit

import "../domain/events"
import "core:encoding/endian"

EvaluationVerdict :: enum u8 {Verified = 1, Rejected = 2}
EvaluationRecorded :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	observation, claim: events.EventRef,
	observed_event_digest: [32]u8,
	verdict: EvaluationVerdict,
	evidence: events.EvidenceId,
	previous_head: [32]u8,
}
EvaluationRecordedBytes :: [203]u8
EvaluationRecordedBodySize :: 171

// Both evaluation and transition records carry two ordered predecessor references.
@(private)
validate_reference_chain :: proc(event, predecessor, claim: events.EventRef, store: events.StoreId, epoch: events.Epoch) -> Error {
	references := [3]events.EventRef{event, predecessor, claim}
	for reference in references {
		if events.validate_event_ref(reference, store, epoch) != .None {
			return .InvalidIdentity
		}
	}
	if claim.sequence >= predecessor.sequence || predecessor.sequence >= event.sequence {
		return .Malformed
	}
	return .None
}

@(private)
write_ref :: proc(bytes: []u8, reference: events.EventRef) {
	reference := reference
	copy(bytes[:16], reference.store[:])
	assert(endian.put_u64(bytes[16:24], .Little, u64(reference.epoch)))
	assert(endian.put_u64(bytes[24:32], .Little, u64(reference.sequence)))
}

@(private)
read_ref :: proc(bytes: []u8) -> events.EventRef {
	reference: events.EventRef
	copy(reference.store[:], bytes[:16])
	epoch, _ := endian.get_u64(bytes[16:24], .Little)
	sequence, _ := endian.get_u64(bytes[24:32], .Little)
	reference.epoch = events.Epoch(epoch)
	reference.sequence = events.Sequence(sequence)
	return reference
}

@(private)
validate_evaluation :: proc(value: EvaluationRecorded, store: events.StoreId, epoch: events.Epoch) -> Error {
	if value.verdict != .Verified && value.verdict != .Rejected {
		return .Unsupported
	}
	empty := events.EvidenceId{}
	if value.evidence == empty {
		return .InvalidIdentity
	}
	return validate_reference_chain(value.reference, value.observation, value.claim, store, epoch)
}

encode_evaluation_recorded :: proc(value: EvaluationRecorded, store: events.StoreId, epoch: events.Epoch) -> (EvaluationRecordedBytes, Error) {
	value := value
	if err := validate_evaluation(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: EvaluationRecordedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 6, 4)
	write_ref(bytes[56:88], value.observation)
	write_ref(bytes[88:120], value.claim)
	copy(bytes[120:152], value.observed_event_digest[:])
	assert(endian.put_u16(bytes[152:154], .Little, 1))
	bytes[154] = u8(value.verdict)
	copy(bytes[155:171], value.evidence[:])
	return bytes, .None
}

decode_evaluation_recorded :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (EvaluationRecorded, Error) {
	env, err := read_envelope(bytes, 6, 4, 115)
	if err != .None {
		return {}, err
	}
	criterion, _ := endian.get_u16(bytes[152:154], .Little)
	if criterion != 1 {
		return {}, .Unsupported
	}
	value := EvaluationRecorded{reference = env.reference, recorded_time = env.recorded_time, previous_head = env.previous_head,
		observation = read_ref(bytes[56:88]), claim = read_ref(bytes[88:120]), verdict = EvaluationVerdict(bytes[154])}
	copy(value.observed_event_digest[:], bytes[120:152])
	copy(value.evidence[:], bytes[155:171])
	if err = validate_evaluation(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

digest_evaluation_recorded :: proc(value: EvaluationRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_evaluation_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:EvaluationRecordedBodySize]), .None
}
