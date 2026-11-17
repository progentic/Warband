package audit

import "../domain/events"
import "core:encoding/endian"

ProposalRecorded :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	task: events.TaskId,
	run: events.RunId,
	proposal: events.ProposalId,
	expected_task_version: u64,
	policy_version: u64,
	approval_required: bool,
	previous_head: [32]u8,
}
ProposalRecordedBytes :: [163]u8
ProposalRecordedBodySize :: 131

encode_proposal_recorded :: proc(value: ProposalRecorded, store: events.StoreId, epoch: events.Epoch) -> (ProposalRecordedBytes, Error) {
	value := value
	if err := validate_proposal_recorded(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: ProposalRecordedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 2)
	copy(bytes[56:72], value.task[:])
	copy(bytes[72:88], value.run[:])
	copy(bytes[88:104], value.proposal[:])
	assert(endian.put_u64(bytes[104:112], .Little, value.expected_task_version))
	assert(endian.put_u64(bytes[112:120], .Little, value.policy_version))
	assert(endian.put_u16(bytes[120:122], .Little, 1))
	// Target and argument length stay zero for NoOp.
	assert(endian.put_u16(bytes[127:129], .Little, 1))
	bytes[129] = 1
	if value.approval_required {
		bytes[130] = 1
	}
	return bytes, .None
}

decode_proposal_recorded :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (ProposalRecorded, Error) {
	envelope, err := read_envelope(bytes, 2, 75)
	if err != .None {
		return {}, err
	}
	action, _ := endian.get_u16(bytes[120:122], .Little)
	argument_length, _ := endian.get_u32(bytes[123:127], .Little)
	criterion, _ := endian.get_u16(bytes[127:129], .Little)
	if action != 1 || bytes[122] != 0 || argument_length != 0 || criterion != 1 || bytes[129] != 1 || bytes[130] > 1 {
		return {}, .Unsupported
	}
	value := ProposalRecorded{reference = envelope.reference, recorded_time = envelope.recorded_time, previous_head = envelope.previous_head, approval_required = bytes[130] == 1}
	copy(value.task[:], bytes[56:72])
	copy(value.run[:], bytes[72:88])
	copy(value.proposal[:], bytes[88:104])
	value.expected_task_version, _ = endian.get_u64(bytes[104:112], .Little)
	value.policy_version, _ = endian.get_u64(bytes[112:120], .Little)
	if validation_error := validate_proposal_recorded(value, store, epoch); validation_error != .None {
		return {}, validation_error
	}
	return value, .None
}

digest_proposal_recorded :: proc(value: ProposalRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_proposal_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:ProposalRecordedBodySize]), .None
}

fingerprint_proposal :: proc(value: ProposalRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_proposal_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data("warband.proposal.v1\x00", bytes[56:ProposalRecordedBodySize]), .None
}

@(private)
validate_proposal_recorded :: proc(value: ProposalRecorded, store: events.StoreId, epoch: events.Epoch) -> Error {
	if events.validate_event_ref(value.reference, store, epoch) != .None {
		return .InvalidIdentity
	}
	empty: [16]u8
	if value.task == events.TaskId(empty) || value.run == events.RunId(empty) || value.proposal == events.ProposalId(empty) {
		return .InvalidIdentity
	}
	if value.expected_task_version == 0 {
		return .Malformed
	}
	if value.policy_version != 1 {
		return .Unsupported
	}
	return .None
}
