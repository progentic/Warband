package audit

import "../domain/events"

TaskCreated :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	task: events.TaskId,
	run: events.RunId,
	command: events.CommandId,
	input_digest: [32]u8,
	evidence: events.EvidenceId,
	previous_head: [32]u8,
}

TaskCreatedBytes :: [184]u8
TaskCreatedBodySize :: 152

encode_task_created :: proc(value: TaskCreated, store: events.StoreId, epoch: events.Epoch) -> (TaskCreatedBytes, Error) {
	value := value
	if err := validate_task_created(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: TaskCreatedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 1)
	copy(bytes[56:72], value.task[:])
	copy(bytes[72:88], value.run[:])
	copy(bytes[88:104], value.command[:])
	copy(bytes[104:136], value.input_digest[:])
	copy(bytes[136:152], value.evidence[:])
	return bytes, .None
}

decode_task_created :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (TaskCreated, Error) {
	envelope, envelope_error := read_envelope(bytes, 1, 96)
	if envelope_error != .None {
		return {}, envelope_error
	}
	value := TaskCreated{reference = envelope.reference, recorded_time = envelope.recorded_time, previous_head = envelope.previous_head}
	copy(value.task[:], bytes[56:72])
	copy(value.run[:], bytes[72:88])
	copy(value.command[:], bytes[88:104])
	copy(value.input_digest[:], bytes[104:136])
	copy(value.evidence[:], bytes[136:152])
	if err := validate_task_created(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

// The previous head is bound by custody.derive_head, outside the event digest.
digest_task_created :: proc(value: TaskCreated, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_task_created(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:TaskCreatedBodySize]), .None
}

@(private)
validate_task_created :: proc(value: TaskCreated, store: events.StoreId, epoch: events.Epoch) -> Error {
	if events.validate_event_ref(value.reference, store, epoch) != .None {
		return .InvalidIdentity
	}
	empty: [16]u8
	if value.task == events.TaskId(empty) || value.run == events.RunId(empty) ||
	   value.command == events.CommandId(empty) || value.evidence == events.EvidenceId(empty) {
		return .InvalidIdentity
	}
	return .None
}
