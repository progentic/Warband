package custody

import "../domain/events"
import "core:encoding/endian"

EpochChange :: struct {
	old: events.Checkpoint,
	authorization: events.AuthorizationId,
	reason: Reason,
	unresolved_pending_record_hash: [32]u8,
	operator_uid: u64,
}
EpochEncoding :: struct {data: [1194]u8, length: int}

encode_epoch :: proc(value: EpochChange, store: events.StoreId, epoch: events.Epoch) -> (EpochEncoding, FormatError) {
	value := value
	if validate_admin_identity(value.old.store, store, value.old.epoch, value.authorization) != .None || value.old.epoch != epoch {
		return {}, .InvalidIdentity
	}
	next, err := events.next_epoch(value.old.epoch)
	if err != .None || !valid_reason(value.reason) {
		return {}, .Malformed
	}
	result: EpochEncoding
	result.length = 170 + value.reason.length
	copy(result.data[:16], value.old.store[:])
	write_word(result.data[16:24], u64(value.old.epoch))
	write_word(result.data[24:32], u64(value.old.sequence))
	copy(result.data[32:64], value.old.head[:])
	write_word(result.data[64:72], u64(next))
	// new_seq at [72:80] is zero; new_head is derived after writing its inputs.
	copy(result.data[112:128], value.authorization[:])
	assert(endian.put_u16(result.data[128:130], .Little, u16(value.reason.length)))
	copy(result.data[130:result.length-40], value.reason.bytes[:value.reason.length])
	copy(result.data[result.length-40:result.length-8], value.unresolved_pending_record_hash[:])
	write_word(result.data[result.length-8:result.length], value.operator_uid)
	head := epoch_payload_head(result.data[:result.length])
	copy(result.data[80:112], head[:])
	return result, .None
}

decode_epoch :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (EpochChange, FormatError) {
	if len(bytes) < 170 || len(bytes) > 1194 {
		return {}, .Malformed
	}
	reason, err := read_reason(bytes[128:len(bytes)-40])
	if err != .None {
		return {}, err
	}
	value := EpochChange{reason = reason, operator_uid = read_word(bytes[len(bytes)-8:])}
	copy(value.old.store[:], bytes[:16])
	value.old.epoch = events.Epoch(read_word(bytes[16:24]))
	value.old.sequence = events.Sequence(read_word(bytes[24:32]))
	copy(value.old.head[:], bytes[32:64])
	copy(value.authorization[:], bytes[112:128])
	copy(value.unresolved_pending_record_hash[:], bytes[len(bytes)-40:len(bytes)-8])
	if validate_admin_identity(value.old.store, store, value.old.epoch, value.authorization) != .None || value.old.epoch != epoch {
		return {}, .InvalidIdentity
	}
	next, advance_error := events.next_epoch(value.old.epoch)
	if advance_error != .None || read_word(bytes[64:72]) != u64(next) || read_word(bytes[72:80]) != 0 {
		return {}, .Malformed
	}
	head := epoch_payload_head(bytes)
	if string(bytes[80:112]) != string(head[:]) {
		return {}, .InvalidChecksum
	}
	return value, .None
}

@(private)
epoch_payload_head :: proc(bytes: []u8) -> [32]u8 {
	input: [1146]u8
	copy(input[:72], bytes[:72])
	// Hash omits new_seq, new_head and the history-only operator UID suffix.
	copy(input[72:], bytes[112:len(bytes)-8])
	return hash_metadata("warband.epoch.v1\x00", input[:len(bytes)-48])
}

// Only for a history payload that decode_epoch has fully validated.
@(private)
decoded_epoch_checkpoint :: proc(payload: []u8, store: events.StoreId) -> events.Checkpoint {
	checkpoint := events.Checkpoint{store = store, epoch = events.Epoch(read_word(payload[64:72]))}
	copy(checkpoint.head[:], payload[80:112])
	return checkpoint
}
