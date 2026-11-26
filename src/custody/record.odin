package custody

import "../domain/events"

FrameOverhead :: 51 + 32 + 32
MaxFrameSize :: FrameOverhead + 1194
FrameEncoding :: struct {data: [MaxFrameSize]u8, length: int}
FramePayload :: union {events.Pledge, Genesis, EpochChange, Rejection}
CustodyRecord :: struct {
	kind: FrameKind,
	ordinal: u64,
	previous_record_hash: [32]u8,
	payload: FramePayload,
}

encode_record :: proc(value: CustodyRecord, store: events.StoreId, epoch: events.Epoch) -> (FrameEncoding, FormatError) {
	if err := validate_frame_position(value.ordinal, value.previous_record_hash); err != .None {
		return {}, err
	}
	_, maximum := payload_bounds(value.kind)
	if maximum == 0 {
		return {}, .Unsupported
	}
	switch payload in value.payload {
	case events.Pledge:
		if value.kind != .Pending && value.kind != .Committed {
			return {}, .Malformed
		}
		bytes, err := encode_pledge(payload, store, epoch)
		if err != .None {
			return {}, .InvalidPledge
		}
		return wrap_payload(value.kind, value.ordinal, value.previous_record_hash, bytes[:]), .None
	case Genesis:
		if value.kind != .Genesis {
			return {}, .Malformed
		}
		if epoch != 1 {
			return {}, .InvalidIdentity
		}
		bytes, err := encode_genesis(payload, store)
		if err != .None {
			return {}, err
		}
		return wrap_payload(value.kind, value.ordinal, value.previous_record_hash, bytes.data[:bytes.length]), .None
	case EpochChange:
		if value.kind != .Epoch {
			return {}, .Malformed
		}
		bytes, err := encode_epoch(payload, store, epoch)
		if err != .None {
			return {}, err
		}
		return wrap_payload(value.kind, value.ordinal, value.previous_record_hash, bytes.data[:bytes.length]), .None
	case Rejection:
		if value.kind != .Rejection {
			return {}, .Malformed
		}
		bytes, err := encode_rejection(payload, store, epoch)
		if err != .None {
			return {}, err
		}
		return wrap_payload(value.kind, value.ordinal, value.previous_record_hash, bytes[:]), .None
	}
	return {}, .Malformed
}

decode_record :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch, expected_ordinal: u64, previous_record_hash: [32]u8) -> (CustodyRecord, FormatError) {
	kind, payload, err := decode_frame_payload(bytes, expected_ordinal, previous_record_hash)
	if err != .None {
		return {}, err
	}
	result := CustodyRecord{kind = kind, ordinal = expected_ordinal, previous_record_hash = previous_record_hash}
	switch kind {
	case .Pending, .Committed:
		value, payload_error := decode_pledge(payload, store, epoch)
		if payload_error != .None {
			return {}, .InvalidPledge
		}
		result.payload = value
	case .Genesis:
		if epoch != 1 {
			return {}, .InvalidIdentity
		}
		value, payload_error := decode_genesis(payload, store)
		if payload_error != .None {
			return {}, payload_error
		}
		result.payload = value
	case .Epoch:
		value, payload_error := decode_epoch(payload, store, epoch)
		if payload_error != .None {
			return {}, payload_error
		}
		result.payload = value
	case .Rejection:
		value, payload_error := decode_rejection(payload, store, epoch)
		if payload_error != .None {
			return {}, payload_error
		}
		result.payload = value
	}
	return result, .None
}
