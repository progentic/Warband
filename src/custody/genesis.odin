package custody

import "../domain/events"
import "core:encoding/endian"
import "core:unicode/utf8"

Reason :: struct {bytes: [1024]u8, length: int}
Genesis :: struct {
	store: events.StoreId,
	epoch: events.Epoch,
	authorization: events.AuthorizationId,
	reason: Reason,
	operator_uid: u64,
}
GenesisEncoding :: struct {data: [1074]u8, length: int}

encode_genesis :: proc(value: Genesis, store: events.StoreId) -> (GenesisEncoding, FormatError) {
	value := value
	if validate_admin_identity(value.store, store, value.epoch, value.authorization) != .None || value.epoch != 1 {
		return {}, .InvalidIdentity
	}
	if !valid_reason(value.reason) {
		return {}, .Malformed
	}
	result: GenesisEncoding
	result.length = 50 + value.reason.length
	copy(result.data[:16], value.store[:])
	write_word(result.data[16:24], u64(value.epoch))
	copy(result.data[24:40], value.authorization[:])
	assert(endian.put_u16(result.data[40:42], .Little, u16(value.reason.length)))
	copy(result.data[42:result.length-8], value.reason.bytes[:value.reason.length])
	write_word(result.data[result.length-8:result.length], value.operator_uid)
	return result, .None
}

decode_genesis :: proc(bytes: []u8, store: events.StoreId) -> (Genesis, FormatError) {
	if len(bytes) < 50 || len(bytes) > 1074 {
		return {}, .Malformed
	}
	reason, err := read_reason(bytes[40:len(bytes)-8])
	if err != .None {
		return {}, err
	}
	value := Genesis{reason = reason, epoch = events.Epoch(read_word(bytes[16:24])), operator_uid = read_word(bytes[len(bytes)-8:])}
	copy(value.store[:], bytes[:16])
	copy(value.authorization[:], bytes[24:40])
	if validate_admin_identity(value.store, store, value.epoch, value.authorization) != .None || value.epoch != 1 {
		return {}, .InvalidIdentity
	}
	return value, .None
}

genesis_head :: proc(value: Genesis, store: events.StoreId) -> ([32]u8, FormatError) {
	encoded, err := encode_genesis(value, store)
	if err != .None {
		return {}, err
	}
	return hash_metadata("warband.genesis.v1\x00", encoded.data[:encoded.length-8]), .None
}

@(private)
validate_admin_identity :: proc(store, expected: events.StoreId, epoch: events.Epoch, authorization: events.AuthorizationId) -> FormatError {
	empty_store := events.StoreId{}
	empty_authorization := events.AuthorizationId{}
	if store == empty_store || store != expected || epoch == 0 || authorization == empty_authorization {
		return .InvalidIdentity
	}
	return .None
}

@(private)
valid_reason :: proc(value: Reason) -> bool {
	value := value
	if value.length < 1 || value.length > len(value.bytes) {
		return false
	}
	for byte in value.bytes[:value.length] {
		if byte == 0 {
			return false
		}
	}
	return utf8.valid_string(string(value.bytes[:value.length]))
}

@(private)
read_reason :: proc(bytes: []u8) -> (Reason, FormatError) {
	if len(bytes) < 2 {
		return {}, .Malformed
	}
	length, _ := endian.get_u16(bytes[:2], .Little)
	if length > 1024 || len(bytes) != 2 + int(length) {
		return {}, .Malformed
	}
	value := Reason{length = int(length)}
	copy(value.bytes[:], bytes[2:])
	if !valid_reason(value) {
		return {}, .Malformed
	}
	return value, .None
}
