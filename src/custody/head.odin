package custody

import "../domain/events"
import "core:encoding/endian"

HeadFile :: struct {
	checkpoint: events.Checkpoint,
	committed_record_hash: [32]u8,
}
HeadBytes :: [134]u8

encode_head_file :: proc(value: HeadFile, store: events.StoreId, epoch: events.Epoch) -> (HeadBytes, FormatError) {
	value := value
	if err := validate_head_identity(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: HeadBytes
	copy(bytes[:4], "WBHD")
	assert(endian.put_u16(bytes[4:6], .Little, 1))
	copy(bytes[6:22], value.checkpoint.store[:])
	write_word(bytes[22:30], u64(value.checkpoint.epoch))
	write_word(bytes[30:38], u64(value.checkpoint.sequence))
	copy(bytes[38:70], value.checkpoint.head[:])
	copy(bytes[70:102], value.committed_record_hash[:])
	checksum := hash_metadata("warband.head.v1\x00", bytes[:102])
	copy(bytes[102:], checksum[:])
	return bytes, .None
}

decode_head_file :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (HeadFile, FormatError) {
	if len(bytes) != size_of(HeadBytes) || string(bytes[:4]) != "WBHD" {
		return {}, .Malformed
	}
	version, _ := endian.get_u16(bytes[4:6], .Little)
	if version != 1 {
		return {}, .Unsupported
	}
	checksum := hash_metadata("warband.head.v1\x00", bytes[:102])
	if string(bytes[102:]) != string(checksum[:]) {
		return {}, .InvalidChecksum
	}
	value: HeadFile
	copy(value.checkpoint.store[:], bytes[6:22])
	value.checkpoint.epoch = events.Epoch(read_word(bytes[22:30]))
	value.checkpoint.sequence = events.Sequence(read_word(bytes[30:38]))
	copy(value.checkpoint.head[:], bytes[38:70])
	copy(value.committed_record_hash[:], bytes[70:102])
	if err := validate_head_identity(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

@(private)
validate_head_identity :: proc(value: HeadFile, store: events.StoreId, epoch: events.Epoch) -> FormatError {
	empty_store := events.StoreId{}
	if value.checkpoint.store == empty_store || value.checkpoint.store != store ||
	   value.checkpoint.epoch == 0 || value.checkpoint.epoch != epoch {
		return .InvalidIdentity
	}
	// Sequence zero represents genesis/epoch metadata; enrollment is checked elsewhere.
	return .None
}
