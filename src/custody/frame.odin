package custody

import "../domain/events"
import "core:encoding/endian"
import "core:crypto/sha2"

FrameKind :: enum u8 {Pending = 1, Committed = 2}
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
	if value.ordinal == 0 {
		return {}, .InvalidOrdinal
	}
	empty_hash: [32]u8
	if value.ordinal == 1 && value.previous_record_hash != empty_hash {
		return {}, .AttestationHistoryFault
	}
	payload, err := encode_pledge(value.pledge, store, epoch)
	if err != .None {
		return {}, .InvalidPledge
	}
	header := frame_header(value.kind, value.ordinal, value.previous_record_hash)
	header_hash := hash_metadata("warband.custody.header.v1\x00", header[:])
	bytes: FrameBytes
	copy(bytes[:51], header[:])
	copy(bytes[51:83], header_hash[:])
	copy(bytes[83:219], payload[:])
	record_hash := hash_metadata("warband.custody.record.v1\x00", bytes[:219])
	copy(bytes[219:], record_hash[:])
	return bytes, .None
}

// Truncated describes bytes only; the caller must establish a repairable final frame.
decode_frame :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch, expected_ordinal: u64, previous_record_hash: [32]u8) -> (Frame, FormatError) {
	if expected_ordinal == 0 {
		return {}, .InvalidOrdinal
	}
	empty_hash: [32]u8
	if expected_ordinal == 1 && previous_record_hash != empty_hash {
		return {}, .AttestationHistoryFault
	}
	if len(bytes) > size_of(FrameBytes) {
		return {}, .Malformed
	}
	kind := FrameKind.Pending
	if len(bytes) > 6 {
		kind = FrameKind(bytes[6])
		if kind != .Pending && kind != .Committed {
			return {}, .Unsupported
		}
	}
	header := frame_header(kind, expected_ordinal, previous_record_hash)
	for expected, index in header {
		if index >= len(bytes) {
			return {}, .Truncated
		}
		if bytes[index] != expected {
			if index == 4 || index == 5 {
				return {}, .Unsupported
			}
			return {}, .AttestationHistoryFault
		}
	}
	header_hash := hash_metadata("warband.custody.header.v1\x00", header[:])
	for expected, index in header_hash {
		if 51 + index >= len(bytes) {
			return {}, .Truncated
		}
		if bytes[51 + index] != expected {
			return {}, .AttestationHistoryFault
		}
	}
	if len(bytes) < size_of(FrameBytes) {
		return {}, .Truncated
	}
	record_hash := hash_metadata("warband.custody.record.v1\x00", bytes[:219])
	if string(bytes[219:]) != string(record_hash[:]) {
		return {}, .AttestationHistoryFault
	}
	pledge, err := decode_pledge(bytes[83:219], store, epoch)
	if err != .None {
		return {}, .InvalidPledge
	}
	return {kind = kind, ordinal = expected_ordinal, previous_record_hash = previous_record_hash, pledge = pledge}, .None
}

@(private)
frame_header :: proc(kind: FrameKind, ordinal: u64, previous: [32]u8) -> [51]u8 {
	previous := previous
	header: [51]u8
	copy(header[:4], "WBCH")
	assert(endian.put_u16(header[4:6], .Little, 1))
	header[6] = u8(kind)
	assert(endian.put_u32(header[7:11], .Little, 136))
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
