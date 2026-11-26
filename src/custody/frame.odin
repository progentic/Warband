package custody

import "../domain/events"
import "core:encoding/endian"
import "core:crypto/sha2"

FrameKind :: enum u8 {Pending = 1, Committed = 2, Genesis = 3, Epoch = 4, Rejection = 5}
Frame :: struct {
	kind: FrameKind,
	ordinal: u64,
	previous_record_hash: [32]u8,
	pledge: events.Pledge,
}
FrameBytes :: [251]u8
FormatError :: enum {None, Malformed, Unsupported, Truncated, InvalidIdentity, InvalidPledge, InvalidOrdinal, AttestationHistoryFault, InvalidChecksum}

encode_frame :: proc(value: Frame, store: events.StoreId, epoch: events.Epoch) -> (FrameBytes, FormatError) {
	if value.kind != .Pending && value.kind != .Committed {
		return {}, .Unsupported
	}
	record := CustodyRecord{kind = value.kind, ordinal = value.ordinal, previous_record_hash = value.previous_record_hash, payload = value.pledge}
	encoded, err := encode_record(record, store, epoch)
	if err != .None {
		return {}, err
	}
	bytes: FrameBytes
	copy(bytes[:], encoded.data[:encoded.length])
	return bytes, .None
}

// Legacy entry point retains the fixed pledge-frame shape and kind restriction.
decode_frame :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch, expected_ordinal: u64, previous_record_hash: [32]u8) -> (Frame, FormatError) {
	if err := validate_frame_position(expected_ordinal, previous_record_hash); err != .None {
		return {}, err
	}
	if len(bytes) > size_of(FrameBytes) {
		return {}, .Malformed
	}
	if len(bytes) > 6 && bytes[6] != 1 && bytes[6] != 2 {
		return {}, .Unsupported
	}
	record, err := decode_record(bytes, store, epoch, expected_ordinal, previous_record_hash)
	if err != .None {
		return {}, err
	}
	pledge, ok := record.payload.(events.Pledge)
	if !ok {
		return {}, .Unsupported
	}
	return {kind = record.kind, ordinal = record.ordinal, previous_record_hash = record.previous_record_hash, pledge = pledge}, .None
}

@(private)
validate_frame_position :: proc(ordinal: u64, previous: [32]u8) -> FormatError {
	if ordinal == 0 {
		return .InvalidOrdinal
	}
	empty: [32]u8
	if ordinal == 1 && previous != empty {
		return .AttestationHistoryFault
	}
	return .None
}

@(private)
payload_bounds :: proc(kind: FrameKind) -> (int, int) {
	switch kind {
	case .Pending, .Committed: return 136, 136
	case .Genesis: return 51, 1074
	case .Epoch: return 171, 1194
	case .Rejection: return 88, 88
	}
	return 0, 0
}

@(private)
wrap_payload :: proc(kind: FrameKind, ordinal: u64, previous: [32]u8, payload: []u8) -> FrameEncoding {
	result: FrameEncoding
	result.length = FrameOverhead + len(payload)
	header := frame_header(kind, u32(len(payload)), ordinal, previous)
	header_hash := hash_metadata("warband.custody.header.v1\x00", header[:])
	copy(result.data[:51], header[:])
	copy(result.data[51:83], header_hash[:])
	copy(result.data[83:result.length-32], payload)
	record_hash := hash_metadata("warband.custody.record.v1\x00", result.data[:result.length-32])
	copy(result.data[result.length-32:result.length], record_hash[:])
	return result
}

// Truncated never authorizes repair; final-frame/history checks belong to recovery.
@(private)
decode_frame_payload :: proc(bytes: []u8, ordinal: u64, previous: [32]u8) -> (FrameKind, []u8, FormatError) {
	if err := validate_frame_position(ordinal, previous); err != .None {
		return {}, nil, err
	}
	if len(bytes) > MaxFrameSize {
		return {}, nil, .Malformed
	}
	prefix := [6]u8{'W', 'B', 'C', 'H', 1, 0}
	for expected, index in prefix {
		if index >= len(bytes) {
			return {}, nil, .Truncated
		}
		if bytes[index] != expected {
			if index >= 4 {
				return {}, nil, .Unsupported
			}
			return {}, nil, .AttestationHistoryFault
		}
	}
	if len(bytes) <= 6 {
		return {}, nil, .Truncated
	}
	kind := FrameKind(bytes[6])
	minimum, maximum := payload_bounds(kind)
	if maximum == 0 {
		return {}, nil, .Unsupported
	}
	payload_size: u64
	for index in 0..<4 {
		if 7+index >= len(bytes) {
			return {}, nil, .Truncated
		}
		payload_size |= u64(bytes[7+index]) << uint(8*index)
		// Minimum sizes are below 256; at most one unknown-byte increment is needed.
		possible := payload_size
		if possible < u64(minimum) {
			possible += u64(1) << uint(8*(index+1))
		}
		if possible > u64(maximum) {
			return {}, nil, .AttestationHistoryFault
		}
	}
	header := frame_header(kind, u32(payload_size), ordinal, previous)
	for index in 11..<len(header) {
		if index >= len(bytes) {
			return {}, nil, .Truncated
		}
		if bytes[index] != header[index] {
			return {}, nil, .AttestationHistoryFault
		}
	}
	header_hash := hash_metadata("warband.custody.header.v1\x00", header[:])
	for expected, index in header_hash {
		if 51+index >= len(bytes) {
			return {}, nil, .Truncated
		}
		if bytes[51+index] != expected {
			return {}, nil, .AttestationHistoryFault
		}
	}
	total := FrameOverhead + int(payload_size)
	if len(bytes) < total {
		return {}, nil, .Truncated
	}
	if len(bytes) > total {
		return {}, nil, .Malformed
	}
	record_hash := hash_metadata("warband.custody.record.v1\x00", bytes[:total-32])
	if string(bytes[total-32:]) != string(record_hash[:]) {
		return {}, nil, .AttestationHistoryFault
	}
	return kind, bytes[83:total-32], .None
}

@(private)
frame_header :: proc(kind: FrameKind, payload_size: u32, ordinal: u64, previous: [32]u8) -> [51]u8 {
	previous := previous
	header: [51]u8
	copy(header[:4], "WBCH")
	assert(endian.put_u16(header[4:6], .Little, 1))
	header[6] = u8(kind)
	assert(endian.put_u32(header[7:11], .Little, payload_size))
	write_word(header[11:19], ordinal)
	copy(header[19:], previous[:])
	return header
}

@(private)
hash_metadata :: proc(domain: string, bytes: []u8) -> [32]u8 {
	prefix: [32]u8
	assert(len(domain) <= len(prefix))
	copy(prefix[:], domain)
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, prefix[:len(domain)])
	sha2.update(&ctx, bytes)
	result: [32]u8
	sha2.final(&ctx, result[:])
	return result
}
