package custody

import "../domain/events"
import "core:encoding/endian"

Rejection :: struct {
	store: events.StoreId,
	epoch: events.Epoch,
	fault_code: u16,
	captured_length: u32,
	request_complete: u8,
	request_digest: [32]u8,
	peer_observed: u8,
	uid, gid, pid: u64,
}
RejectionBytes :: [88]u8

encode_rejection :: proc(value: Rejection, store: events.StoreId, epoch: events.Epoch) -> (RejectionBytes, FormatError) {
	value := value
	if err := validate_rejection(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: RejectionBytes
	copy(bytes[:16], value.store[:])
	write_word(bytes[16:24], u64(value.epoch))
	assert(endian.put_u16(bytes[24:26], .Little, value.fault_code))
	assert(endian.put_u32(bytes[26:30], .Little, value.captured_length))
	bytes[30] = value.request_complete
	copy(bytes[31:63], value.request_digest[:])
	bytes[63] = value.peer_observed
	write_word(bytes[64:72], value.uid)
	write_word(bytes[72:80], value.gid)
	write_word(bytes[80:88], value.pid)
	return bytes, .None
}

decode_rejection :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (Rejection, FormatError) {
	if len(bytes) != size_of(RejectionBytes) {
		return {}, .Malformed
	}
	value: Rejection
	copy(value.store[:], bytes[:16])
	value.epoch = events.Epoch(read_word(bytes[16:24]))
	value.fault_code, _ = endian.get_u16(bytes[24:26], .Little)
	value.captured_length, _ = endian.get_u32(bytes[26:30], .Little)
	value.request_complete = bytes[30]
	copy(value.request_digest[:], bytes[31:63])
	value.peer_observed = bytes[63]
	value.uid = read_word(bytes[64:72])
	value.gid = read_word(bytes[72:80])
	value.pid = read_word(bytes[80:88])
	if err := validate_rejection(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

denial_digest :: proc(prefix: []u8, request_complete: u8) -> ([32]u8, FormatError) {
	if len(prefix) > 65547 || request_complete > 1 {
		return {}, .Malformed
	}
	input: [65552]u8
	assert(endian.put_u32(input[:4], .Little, u32(len(prefix))))
	input[4] = request_complete
	copy(input[5:], prefix)
	return hash_metadata("warband.custody.denial.v1\x00", input[:5+len(prefix)]), .None
}

@(private)
validate_rejection :: proc(value: Rejection, store: events.StoreId, epoch: events.Epoch) -> FormatError {
	empty_store := events.StoreId{}
	if value.store == empty_store || value.store != store || value.epoch != epoch {
		return .InvalidIdentity
	}
	if value.fault_code < 1 || value.fault_code > 19 || value.captured_length > 65547 || value.request_complete > 1 || value.peer_observed > 1 {
		return .Malformed
	}
	if value.peer_observed == 0 && (value.uid != 0 || value.gid != 0 || value.pid != 0) {
		return .Malformed
	}
	return .None
}
