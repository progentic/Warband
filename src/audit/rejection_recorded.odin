package audit

import "../domain/events"
import "core:encoding/endian"

RejectionRecorded :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	producer: u16,
	stage: u8,
	reason: u16,
	related: Maybe(events.EventRef),
	rejected_input_digest: [32]u8,
	previous_head: [32]u8,
}
RejectionEncoding :: struct {data: [156]u8, length: int}

@(private)
validate_rejection_recorded :: proc(value: RejectionRecorded, store: events.StoreId, epoch: events.Epoch) -> Error {
	producer_for_stage := [7]u16{1, 2, 2, 3, 4, 5, 5}
	if value.stage < 1 || value.stage > 7 || value.reason < 1 || value.reason > 13 {
		return .Unsupported
	}
	if value.producer != producer_for_stage[value.stage-1] {
		return .Unsupported
	}
	if events.validate_event_ref(value.reference, store, epoch) != .None {
		return .InvalidIdentity
	}
	if ref, present := value.related.(events.EventRef); present {
		if events.validate_event_ref(ref, store, epoch) != .None {
			return .InvalidIdentity
		}
		if ref.sequence >= value.reference.sequence {
			return .Malformed
		}
	}
	return .None
}

encode_rejection_recorded :: proc(value: RejectionRecorded, store: events.StoreId, epoch: events.Epoch) -> (RejectionEncoding, Error) {
	value := value
	if err := validate_rejection_recorded(value, store, epoch); err != .None {
		return {}, err
	}
	result: RejectionEncoding
	result.length = 124
	if ref, present := value.related.(events.EventRef); present {
		result.length = 156
		result.data[59] = 1
		write_ref(result.data[60:92], ref)
	}
	bytes := result.data[:result.length]
	write_envelope(bytes, {value.reference, value.recorded_time, value.previous_head}, 8, value.producer)
	bytes[56] = value.stage
	assert(endian.put_u16(bytes[57:59], .Little, value.reason))
	copy(bytes[len(bytes)-64:len(bytes)-32], value.rejected_input_digest[:])
	return result, .None
}

decode_rejection_recorded :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (RejectionRecorded, Error) {
	if len(bytes) != 124 && len(bytes) != 156 {
		return {}, .Malformed
	}
	producer, _ := endian.get_u16(bytes[48:50], .Little)
	env, err := read_envelope(bytes, 8, producer, len(bytes)-88)
	if err != .None {
		return {}, err
	}
	if (len(bytes) == 124 && bytes[59] != 0) || (len(bytes) == 156 && bytes[59] != 1) {
		return {}, .Malformed
	}
	value := RejectionRecorded{reference = env.reference, recorded_time = env.recorded_time,
		previous_head = env.previous_head, producer = producer, stage = bytes[56]}
	value.reason, _ = endian.get_u16(bytes[57:59], .Little)
	if bytes[59] == 1 {
		value.related = read_ref(bytes[60:92])
	}
	copy(value.rejected_input_digest[:], bytes[len(bytes)-64:len(bytes)-32])
	if err = validate_rejection_recorded(value, store, epoch); err != .None {
		return {}, err
	}
	return value, .None
}

digest_rejection_recorded :: proc(value: RejectionRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	encoded, err := encode_rejection_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, encoded.data[:encoded.length-32]), .None
}
