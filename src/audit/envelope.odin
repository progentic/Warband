package audit

import "../domain/events"
import "core:encoding/endian"
import "core:crypto/sha2"

EventDomain :: "warband.event.v1\x00"
Error :: enum {None, Malformed, Unsupported, InvalidIdentity}

@(private)
Envelope :: struct {reference: events.EventRef, recorded_time: u64, previous_head: [32]u8}

@(private)
write_envelope :: proc(bytes: []u8, value: Envelope, kind, producer: u16) {
	value := value
	copy(bytes[:4], "WBEV")
	assert(endian.put_u16(bytes[4:6], .Little, 1))
	assert(endian.put_u16(bytes[6:8], .Little, kind))
	copy(bytes[8:24], value.reference.store[:])
	assert(endian.put_u64(bytes[24:32], .Little, u64(value.reference.epoch)))
	assert(endian.put_u64(bytes[32:40], .Little, u64(value.reference.sequence)))
	assert(endian.put_u64(bytes[40:48], .Little, value.recorded_time))
	assert(endian.put_u16(bytes[48:50], .Little, producer))
	assert(endian.put_u16(bytes[50:52], .Little, 1))
	assert(endian.put_u32(bytes[52:56], .Little, u32(len(bytes)-88)))
	copy(bytes[len(bytes)-32:], value.previous_head[:])
}

@(private)
read_envelope :: proc(bytes: []u8, expected_kind, expected_producer: u16, expected_payload_size: int) -> (Envelope, Error) {
	if len(bytes) != expected_payload_size+88 || string(bytes[:4]) != "WBEV" {
		return {}, .Malformed
	}
	version, _ := endian.get_u16(bytes[4:6], .Little)
	kind, _ := endian.get_u16(bytes[6:8], .Little)
	producer, _ := endian.get_u16(bytes[48:50], .Little)
	producer_version, _ := endian.get_u16(bytes[50:52], .Little)
	if version != 1 || kind != expected_kind || producer != expected_producer || producer_version != 1 {
		return {}, .Unsupported
	}
	payload_size, _ := endian.get_u32(bytes[52:56], .Little)
	if payload_size != u32(expected_payload_size) {
		return {}, .Malformed
	}
	value: Envelope
	copy(value.reference.store[:], bytes[8:24])
	epoch, _ := endian.get_u64(bytes[24:32], .Little)
	sequence, _ := endian.get_u64(bytes[32:40], .Little)
	value.reference.epoch = events.Epoch(epoch)
	value.reference.sequence = events.Sequence(sequence)
	value.recorded_time, _ = endian.get_u64(bytes[40:48], .Little)
	copy(value.previous_head[:], bytes[len(bytes)-32:])
	return value, .None
}

@(private)
hash_event_data :: proc(domain: string, bytes: []u8) -> [32]u8 {
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
