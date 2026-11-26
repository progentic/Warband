package custody

import "../domain/events"
import "core:encoding/endian"
import "core:crypto/sha2"

PledgeBytes :: [136]u8
LinkDomain :: "warband.link.v1\x00"
#assert(len(LinkDomain) == 16)

Error :: enum {None, InvalidLength, InvalidIdentity, InvalidSequence, InvalidLink}

encode_pledge :: proc(value: events.Pledge, store: events.StoreId, epoch: events.Epoch) -> (PledgeBytes, Error) {
	value := value
	if err := validate_pledge(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: PledgeBytes
	copy(bytes[:16], value.store[:])
	write_word(bytes[16:24], u64(value.epoch))
	write_word(bytes[24:32], u64(value.previous_sequence))
	copy(bytes[32:64], value.previous_head[:])
	write_word(bytes[64:72], u64(value.sequence))
	copy(bytes[72:104], value.head[:])
	copy(bytes[104:], value.digest[:])
	return bytes, .None
}

decode_pledge :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (events.Pledge, Error) {
	if len(bytes) != size_of(PledgeBytes) {
		return {}, .InvalidLength
	}
	value: events.Pledge
	copy(value.store[:], bytes[:16])
	value.epoch = events.Epoch(read_word(bytes[16:24]))
	value.previous_sequence = events.Sequence(read_word(bytes[24:32]))
	copy(value.previous_head[:], bytes[32:64])
	value.sequence = events.Sequence(read_word(bytes[64:72]))
	copy(value.head[:], bytes[72:104])
	copy(value.digest[:], bytes[104:])
	if err := validate_pledge(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

// This calculates bytes, not permission or proof of journal contents.
derive_head :: proc(value: events.Pledge) -> [32]u8 {
	value := value
	input: [112]u8
	copy(input[:16], LinkDomain)
	copy(input[16:32], value.store[:])
	write_word(input[32:40], u64(value.epoch))
	write_word(input[40:48], u64(value.sequence))
	copy(input[48:80], value.previous_head[:])
	copy(input[80:], value.digest[:])
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, input[:])
	result: [32]u8
	sha2.final(&ctx, result[:])
	return result
}

@(private)
validate_pledge :: proc(value: events.Pledge, store: events.StoreId, epoch: events.Epoch) -> Error {
	reference := events.EventRef{store = value.store, epoch = value.epoch, sequence = value.sequence}
	if events.validate_event_ref(reference, store, epoch) != .None {
		return .InvalidIdentity
	}
	next, err := events.next_sequence(value.previous_sequence)
	if err != .None || value.sequence != next {
		return .InvalidSequence
	}
	if value.head != derive_head(value) {
		return .InvalidLink
	}
	return .None
}

@(private)
write_word :: proc(bytes: []u8, value: u64) {
	assert(endian.put_u64(bytes, .Little, value))
}

@(private)
read_word :: proc(bytes: []u8) -> u64 {
	value, ok := endian.get_u64(bytes, .Little)
	assert(ok)
	return value
}
