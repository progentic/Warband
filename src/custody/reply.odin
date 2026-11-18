package custody

import "../domain/events"
import "core:encoding/endian"

ReplyStatus :: enum u16 {
	Ready, PendingEventMissing, PendingConfirmation, HeadPublicationPending, AttestationUncertain,
	ConfirmedResponsePending, TornFinalRecord, UnattestedTail, IntegrityFault, CheckpointInconsistent,
	AttestationHistoryFault, CheckpointMissing, StoreIdentityMismatch, EpochMismatch,
	CheckpointStorageFault, CustodianAuthFault, CheckpointConflict, CustodyBoundaryFault, Malformed, Unsupported,
}

// Supplied by the caller. The wire cannot establish authentication or select the request.
ReplyContext :: struct {
	authenticated: bool,
	operation: Operation,
	request_digest: [32]u8,
	store: events.StoreId,
	epoch: events.Epoch,
	after_ordinal: u64,
}
RejectionFrameBytes :: [203]u8
Reply :: struct {
	status: ReplyStatus,
	receipt: [32]u8,
	committed: events.Checkpoint,
	pending: Maybe(events.Pledge),
	tip: u64,
	rejection: Maybe(RejectionFrameBytes),
}
ReplyEncoding :: struct {data: [490]u8, length: int}

@(private)
validate_reply :: proc(value: Reply, ctx: ReplyContext) -> FormatError {
	if u8(ctx.operation) < 1 || u8(ctx.operation) > 5 || u16(value.status) > 19 {
		return .Unsupported
	}
	zero: [32]u8
	if value.status == .CheckpointStorageFault && value.receipt != zero {
		return .Malformed
	}
	empty := events.Checkpoint{}
	if !ctx.authenticated {
		if value.status == .Ready || value.committed != empty || value.pending != nil || value.tip != 0 || value.rejection != nil {
			return .Malformed
		}
		return .None
	}
	if value.committed == empty {
		if value.pending != nil || (value.status == .Ready && ctx.operation != .Enroll && ctx.operation != .EpochChange) {
			return .Malformed
		}
	} else if err := validate_head_identity({checkpoint = value.committed}, ctx.store, ctx.epoch); err != .None {
		return err
	}
	if value.status == .Ready && ctx.operation == .Verify && ctx.after_ordinal > value.tip {
		return .InvalidOrdinal
	}
	if frame, present := value.rejection.(RejectionFrameBytes); present {
		if ctx.operation != .Verify || value.status != .Ready || frame[6] != u8(FrameKind.Rejection) {
			return .Malformed
		}
		ordinal := read_word(frame[11:19])
		if ordinal <= ctx.after_ordinal || ordinal > value.tip {
			return .InvalidOrdinal
		}
		// Structural frame checks only. History verification binds the predecessor and receipt epoch.
		previous: [32]u8
		copy(previous[:], frame[19:51])
		receipt_epoch := events.Epoch(read_word(frame[99:107]))
		_, err := decode_record(frame[:], ctx.store, receipt_epoch, ordinal, previous)
		return err
	}
	return .None
}

encode_reply :: proc(value: Reply, ctx: ReplyContext) -> (ReplyEncoding, FormatError) {
	value := value
	ctx := ctx
	if !ctx.authenticated {
		value.committed = {}
		value.tip = 0
		value.pending = nil
		value.rejection = nil
	}
	if err := validate_reply(value, ctx); err != .None {
		return {}, err
	}
	result: ReplyEncoding
	bytes := result.data[:]
	copy(bytes[:4], "WBRS")
	assert(endian.put_u16(bytes[4:6], .Little, 1))
	bytes[6] = u8(ctx.operation)
	assert(endian.put_u16(bytes[7:9], .Little, u16(value.status)))
	copy(bytes[13:45], ctx.request_digest[:])
	copy(bytes[45:77], value.receipt[:])
	copy(bytes[77:93], value.committed.store[:])
	write_word(bytes[93:101], u64(value.committed.epoch))
	write_word(bytes[101:109], u64(value.committed.sequence))
	copy(bytes[109:141], value.committed.head[:])
	offset := 142
	if pledge, present := value.pending.(events.Pledge); present {
		encoded, err := encode_pledge(pledge, ctx.store, ctx.epoch)
		if err != .None { return {}, .InvalidPledge }
		bytes[141] = 1
		copy(bytes[offset:offset+136], encoded[:])
		offset += 136
	}
	write_word(bytes[offset:offset+8], value.tip)
	offset += 9
	if frame, present := value.rejection.(RejectionFrameBytes); present {
		bytes[offset-1] = 1
		copy(bytes[offset:offset+203], frame[:])
		offset += 203
	}
	result.length = offset
	assert(endian.put_u32(bytes[9:13], .Little, u32(offset-13)))
	return result, .None
}

decode_reply :: proc(bytes: []u8, ctx: ReplyContext) -> (Reply, FormatError) {
	ctx := ctx
	if len(bytes) != 151 && len(bytes) != 287 && len(bytes) != 354 && len(bytes) != 490 {
		return {}, .Malformed
	}
	if string(bytes[:4]) != "WBRS" { return {}, .Malformed }
	version, _ := endian.get_u16(bytes[4:6], .Little)
	status, _ := endian.get_u16(bytes[7:9], .Little)
	if version != 1 || bytes[6] < 1 || bytes[6] > 5 || status > 19 { return {}, .Unsupported }
	length, _ := endian.get_u32(bytes[9:13], .Little)
	if bytes[6] != u8(ctx.operation) || int(length) != len(bytes)-13 || string(bytes[13:45]) != string(ctx.request_digest[:]) {
		return {}, .Malformed
	}
	with_pending := len(bytes) == 287 || len(bytes) == 490
	with_rejection := len(bytes) == 354 || len(bytes) == 490
	offset := 142
	if with_pending { offset += 136 }
	if bytes[141] != u8(with_pending) || bytes[offset+8] != u8(with_rejection) {
		return {}, .Malformed
	}
	if !ctx.authenticated && (with_pending || with_rejection) { return {}, .Malformed }
	value := Reply{status = ReplyStatus(status), tip = read_word(bytes[offset:offset+8])}
	copy(value.receipt[:], bytes[45:77])
	copy(value.committed.store[:], bytes[77:93])
	value.committed.epoch = events.Epoch(read_word(bytes[93:101]))
	value.committed.sequence = events.Sequence(read_word(bytes[101:109]))
	copy(value.committed.head[:], bytes[109:141])
	if with_pending {
		pledge, err := decode_pledge(bytes[142:offset], ctx.store, ctx.epoch)
		if err != .None { return {}, .InvalidPledge }
		value.pending = pledge
	}
	if with_rejection {
		frame: RejectionFrameBytes
		copy(frame[:], bytes[offset+9:])
		value.rejection = frame
	}
	if err := validate_reply(value, ctx); err != .None { return {}, err }
	return value, .None
}
