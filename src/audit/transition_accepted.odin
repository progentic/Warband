package audit

import "../domain/events"
import "core:encoding/endian"

TransitionAccepted :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	evaluation, claim: events.EventRef,
	transition: events.TransitionId,
	expected_task_version, expected_control_revision: u64,
	previous_head: [32]u8,
}
TransitionAcceptedBytes :: [193]u8
TransitionAcceptedBodySize :: 161

@(private)
validate_transition :: proc(value: TransitionAccepted, store: events.StoreId, epoch: events.Epoch) -> Error {
	empty := events.TransitionId{}
	if value.transition == empty {
		return .InvalidIdentity
	}
	if value.expected_task_version == 0 || value.expected_task_version == max(u64) {
		return .Malformed
	}
	return validate_reference_chain(value.reference, value.evaluation, value.claim, store, epoch)
}

encode_transition_accepted :: proc(value: TransitionAccepted, store: events.StoreId, epoch: events.Epoch) -> (TransitionAcceptedBytes, Error) {
	value := value
	if err := validate_transition(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: TransitionAcceptedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 7, 5)
	write_ref(bytes[56:88], value.evaluation)
	write_ref(bytes[88:120], value.claim)
	copy(bytes[120:136], value.transition[:])
	assert(endian.put_u64(bytes[136:144], .Little, value.expected_task_version))
	assert(endian.put_u64(bytes[144:152], .Little, value.expected_control_revision))
	assert(endian.put_u64(bytes[152:160], .Little, value.expected_task_version+1))
	bytes[160] = 2
	return bytes, .None
}

decode_transition_accepted :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (TransitionAccepted, Error) {
	env, err := read_envelope(bytes, 7, 5, 105)
	if err != .None {
		return {}, err
	}
	if bytes[160] != 2 {
		return {}, .Unsupported
	}
	value := TransitionAccepted{reference = env.reference, recorded_time = env.recorded_time, previous_head = env.previous_head,
		evaluation = read_ref(bytes[56:88]), claim = read_ref(bytes[88:120])}
	copy(value.transition[:], bytes[120:136])
	value.expected_task_version, _ = endian.get_u64(bytes[136:144], .Little)
	value.expected_control_revision, _ = endian.get_u64(bytes[144:152], .Little)
	if err = validate_transition(value, store, epoch); err != .None {
		return {}, err
	}
	new_version, _ := endian.get_u64(bytes[152:160], .Little)
	if new_version != value.expected_task_version+1 {
		return {}, .Malformed
	}
	return value, .None
}

digest_transition_accepted :: proc(value: TransitionAccepted, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_transition_accepted(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:TransitionAcceptedBodySize]), .None
}
