package custody

import "../domain/events"
import "core:encoding/endian"

Operation :: enum u8 {Prepare = 1, Confirm, Verify, Enroll, EpochChange}
VerifyRequest :: struct {store: events.StoreId, epoch: events.Epoch, after_ordinal: u64}
EnrollmentRequest :: struct {store: events.StoreId, epoch: events.Epoch, authorization: events.AuthorizationId, reason: Reason}
EpochRequest :: struct {old: events.Checkpoint, authorization: events.AuthorizationId, reason: Reason, unresolved_pending_record_hash: [32]u8}
RequestPayload :: union {events.Pledge, VerifyRequest, EnrollmentRequest, EpochRequest}
Request :: struct {operation: Operation, payload: RequestPayload}
MaxRequestSize :: 11 + 1194 - 8
RequestEncoding :: struct {data: [MaxRequestSize]u8, length: int}

@(private)
wrap_request :: proc(operation: Operation, payload: []u8) -> RequestEncoding {
	result: RequestEncoding
	result.length = 11 + len(payload)
	copy(result.data[:4], "WBCR")
	assert(endian.put_u16(result.data[4:6], .Little, 1))
	result.data[6] = u8(operation)
	assert(endian.put_u32(result.data[7:11], .Little, u32(len(payload))))
	copy(result.data[11:result.length], payload)
	return result
}

@(private)
valid_verify_scope :: proc(value: VerifyRequest, store: events.StoreId, epoch: events.Epoch) -> bool {
	empty := events.StoreId{}
	return store != empty && value.store == store && value.epoch == epoch
}

encode_request :: proc(value: Request, store: events.StoreId, epoch: events.Epoch) -> (RequestEncoding, FormatError) {
	switch value.operation {
	case .Prepare, .Confirm:
		p, ok := value.payload.(events.Pledge)
		if !ok {
			return {}, .Malformed
		}
		bytes, err := encode_pledge(p, store, epoch)
		if err != .None {
			return {}, .InvalidPledge
		}
		return wrap_request(value.operation, bytes[:]), .None
	case .Verify:
		p, ok := value.payload.(VerifyRequest)
		if !ok {
			return {}, .Malformed
		}
		if !valid_verify_scope(p, store, epoch) {
			return {}, .InvalidIdentity
		}
		bytes: [32]u8
		copy(bytes[:16], p.store[:])
		write_word(bytes[16:24], u64(p.epoch))
		write_word(bytes[24:], p.after_ordinal)
		return wrap_request(.Verify, bytes[:]), .None
	case .Enroll:
		p, ok := value.payload.(EnrollmentRequest)
		if !ok {
			return {}, .Malformed
		}
		bytes, err := encode_genesis({store=p.store, epoch=p.epoch, authorization=p.authorization, reason=p.reason}, store)
		if err != .None {
			return {}, err
		}
		return wrap_request(.Enroll, bytes.data[:bytes.length-8]), .None
	case .EpochChange:
		p, ok := value.payload.(EpochRequest)
		if !ok {
			return {}, .Malformed
		}
		bytes, err := encode_epoch({old=p.old, authorization=p.authorization, reason=p.reason, unresolved_pending_record_hash=p.unresolved_pending_record_hash}, store, epoch)
		if err != .None {
			return {}, err
		}
		return wrap_request(.EpochChange, bytes.data[:bytes.length-8]), .None
	}
	return {}, .Unsupported
}

decode_request :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (Request, FormatError) {
	if len(bytes) < 11 || len(bytes) > MaxRequestSize || string(bytes[:4]) != "WBCR" {
		return {}, .Malformed
	}
	version, _ := endian.get_u16(bytes[4:6], .Little)
	if version != 1 || bytes[6] < 1 || bytes[6] > 5 {
		return {}, .Unsupported
	}
	length, _ := endian.get_u32(bytes[7:11], .Little)
	payload := bytes[11:]
	if int(length) != len(payload) {
		return {}, .Malformed
	}
	op := Operation(bytes[6])
	switch op {
	case .Prepare, .Confirm:
		if len(payload) != size_of(PledgeBytes) {
			return {}, .Malformed
		}
		p, err := decode_pledge(payload, store, epoch)
		if err != .None {
			return {}, .InvalidPledge
		}
		return {op,p}, .None
	case .Verify:
		if len(payload) != 32 {
			return {}, .Malformed
		}
		p := VerifyRequest{epoch=events.Epoch(read_word(payload[16:24])), after_ordinal=read_word(payload[24:])}
		copy(p.store[:], payload[:16])
		if !valid_verify_scope(p, store, epoch) {
			return {}, .InvalidIdentity
		}
		return {op,p}, .None
	case .Enroll:
		// Append eight internal padding bytes for the existing history decoder.
		// It enforces the exact counted reason. No UID enters the request value.
		history: GenesisEncoding
		if len(payload)+8 > len(history.data) {
			return {}, .Malformed
		}
		copy(history.data[:], payload)
		p, err := decode_genesis(history.data[:len(payload)+8], store)
		if err != .None {
			return {}, err
		}
		return {op,EnrollmentRequest{p.store,p.epoch,p.authorization,p.reason}}, .None
	case .EpochChange:
		history: EpochEncoding
		copy(history.data[:], payload)
		p, err := decode_epoch(history.data[:len(payload)+8], store, epoch)
		if err != .None {
			return {}, err
		}
		return {op,EpochRequest{p.old,p.authorization,p.reason,p.unresolved_pending_record_hash}}, .None
	}
	return {}, .Unsupported
}

digest_request :: proc(value: Request, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, FormatError) {
	encoded, err := encode_request(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_metadata("warband.request.v1\x00", encoded.data[:encoded.length]), .None
}
