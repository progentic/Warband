package audit

import "../domain/events"
import "core:encoding/endian"
import "core:crypto/sha2"

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
EventDomain :: "warband.event.v1\x00"
Error :: enum {None, Malformed, Unsupported, InvalidIdentity}

encode_task_created :: proc(value: TaskCreated, store: events.StoreId, epoch: events.Epoch) -> (TaskCreatedBytes, Error) {
	value := value
	if err := validate_task_created(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: TaskCreatedBytes
	copy(bytes[:4], "WBEV")
	assert(endian.put_u16(bytes[4:6], .Little, 1))
	assert(endian.put_u16(bytes[6:8], .Little, 1))
	copy(bytes[8:24], value.reference.store[:])
	assert(endian.put_u64(bytes[24:32], .Little, u64(value.reference.epoch)))
	assert(endian.put_u64(bytes[32:40], .Little, u64(value.reference.sequence)))
	assert(endian.put_u64(bytes[40:48], .Little, value.recorded_time))
	assert(endian.put_u16(bytes[48:50], .Little, 1))
	assert(endian.put_u16(bytes[50:52], .Little, 1))
	assert(endian.put_u32(bytes[52:56], .Little, 96))
	copy(bytes[56:72], value.task[:])
	copy(bytes[72:88], value.run[:])
	copy(bytes[88:104], value.command[:])
	copy(bytes[104:136], value.input_digest[:])
	copy(bytes[136:152], value.evidence[:])
	copy(bytes[152:], value.previous_head[:])
	return bytes, .None
}

decode_task_created :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (TaskCreated, Error) {
	if len(bytes) != size_of(TaskCreatedBytes) {
		return {}, .Malformed
	}
	if string(bytes[:4]) != "WBEV" {
		return {}, .Malformed
	}
	version, _ := endian.get_u16(bytes[4:6], .Little)
	kind, _ := endian.get_u16(bytes[6:8], .Little)
	producer, _ := endian.get_u16(bytes[48:50], .Little)
	producer_version, _ := endian.get_u16(bytes[50:52], .Little)
	if version != 1 || kind != 1 || producer != 1 || producer_version != 1 {
		return {}, .Unsupported
	}
	payload_size, _ := endian.get_u32(bytes[52:56], .Little)
	if payload_size != 96 {
		return {}, .Malformed
	}
	value: TaskCreated
	copy(value.reference.store[:], bytes[8:24])
	epoch_value, _ := endian.get_u64(bytes[24:32], .Little)
	sequence, _ := endian.get_u64(bytes[32:40], .Little)
	value.reference.epoch = events.Epoch(epoch_value)
	value.reference.sequence = events.Sequence(sequence)
	value.recorded_time, _ = endian.get_u64(bytes[40:48], .Little)
	copy(value.task[:], bytes[56:72])
	copy(value.run[:], bytes[72:88])
	copy(value.command[:], bytes[88:104])
	copy(value.input_digest[:], bytes[104:136])
	copy(value.evidence[:], bytes[136:152])
	copy(value.previous_head[:], bytes[152:])
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
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	domain: [len(EventDomain)]u8
	copy(domain[:], EventDomain)
	sha2.update(&ctx, domain[:])
	sha2.update(&ctx, bytes[:TaskCreatedBodySize])
	digest: [32]u8
	sha2.final(&ctx, digest[:])
	return digest, .None
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
