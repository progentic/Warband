package custody_linux

import c "../"
import e "../../domain/events"
import "core:encoding/endian"

Service :: struct {
	store: e.StoreId,
	view: c.HistoryView,
	roles: c.PeerConfiguration,
	fault: bool,
}
Result :: struct {
	status: c.ReplyStatus,
	receipt: [32]u8,
	rejection: Maybe(c.RejectionFrameBytes),
}

@(private)
read_history_bytes :: proc() -> ([]u8, bool) {
	size := wb_size("history")
	if size == -1 { return nil, true }
	if size < 0 || size > 8*1024*1024 { return nil, false }
	data, err := make([]u8, int(size), context.allocator)
	if err != nil { return nil, false }
	return data, wb_read("history", raw_data(data), uintptr(size)) == 0
}

@(private)
read_head_bytes :: proc(store: e.StoreId) -> (Maybe(c.HeadFile), bool, bool) {
	size := wb_size("head")
	if size == -1 { return nil, true, false }
	if size < 0 { return nil, false, true }
	if size != size_of(c.HeadBytes) { return nil, true, true } // Recover only from validated history below.
	bytes: c.HeadBytes
	if wb_read("head", &bytes, size_of(bytes)) != 0 { return nil, false, true }
	epoch, _ := endian.get_u64(bytes[22:30], .Little)
	head, err := c.decode_head_file(bytes[:], store, e.Epoch(epoch))
	if err == .InvalidIdentity || err == .Unsupported { return nil, false, true }
	if err != .None { return nil, true, true }
	return head, true, true
}

// Only called for validated complete frames (including a validated prefix before a torn tail).
@(private)
frame_size :: proc(bytes: []u8) -> int {
	n, _ := endian.get_u32(bytes[7:11], .Little)
	return c.FrameOverhead + int(n)
}

@(private)
record_hash :: proc(frame: []u8) -> [32]u8 {
	h: [32]u8
	copy(h[:], frame[len(frame)-32:])
	return h
}

publish_head :: proc(head: c.HeadFile) -> bool {
	cp := head.checkpoint
	encoded, err := c.encode_head_file(head, cp.store, cp.epoch)
	return err == .None && wb_publish(&encoded, size_of(encoded)) == 0
}

recover_checkpoint :: proc(s: ^Service) -> bool {
	start := wb_millis()
	history, ok := read_history_bytes()
	head, readable, present := read_head_bytes(s.store)
	if !ok || !readable || start < 0 { return false }
	view, status := c.validate_custody_history(history, head, s.store)
	if present && head == nil && view.committed.checkpoint.epoch == 0 { return false }
	if status == .TornFinalRecord {
		end := 0
		for i := u64(0); i < view.ordinal; i += 1 { end += frame_size(history[end:]) }
		elapsed := wb_millis() - start
		if elapsed < 0 || elapsed >= 60_000 { return false }
		if wb_sync_history(i64(end)) != 0 { return false }
		// The validator already verified every retained byte.
		status = .Consistent
	}
	now := wb_millis()
	if now < start || now-start >= 60_000 { return false }
	#partial switch status {
	case .Consistent, .Unenrolled, .HeadPublicationPending, .CheckpointInconsistent:
	case: return false
	}
	if len(history) > 0 && wb_sync_history(-1) != 0 { return false }
	// Re-publish even a matching head on explicit startup to settle a previous
	// rename whose directory sync may have failed before process exit.
	if view.committed.checkpoint.epoch != 0 {
		if !publish_head(view.committed) { return false }
	}
	now = wb_millis()
	if now < start || now-start >= 60_000 { return false }
	s.view = view
	return true
}

// Serialize one append under the lifetime single-writer lock. Only enroll/deny may create history.
@(private)
append_record :: proc(s: ^Service, kind: c.FrameKind, payload: c.FramePayload, epoch: e.Epoch) -> Result {
	rec := c.CustodyRecord{kind, s.view.ordinal+1, s.view.record_hash, payload}
	frame, err := c.encode_record(rec, s.store, epoch)
	if err != .None { return {status = .Malformed} }
	bytes := frame.data[:frame.length]
	// Before GENESIS an existing history name may still need a directory sync.
	first := s.view.ordinal == 0
	sync_directory := s.view.committed.checkpoint.epoch == 0
	if wb_append(raw_data(bytes), uintptr(len(bytes)), i32(first), i32(sync_directory)) != 0 {
		s.fault = true
		return {status = .CheckpointStorageFault}
	}
	s.view.ordinal += 1
	s.view.record_hash = record_hash(bytes)
	return {receipt = s.view.record_hash}
}

prepare_checkpoint :: proc(s: ^Service, pledge: e.Pledge) -> Result {
	_, valid := load_validated(s)
	if !valid { s.fault = true; return {status = .AttestationHistoryFault} }
	pending, live := s.view.pending.(e.Pledge)
	p: ^e.Pledge
	if live { p = &pending }
	#partial switch e.classify_prepare(pledge, s.view.committed.checkpoint, p) {
	case .PendingReplay: return {receipt = s.view.pending_record_hash}
	case .EligiblePledge:
	case: return {status = .CheckpointConflict}
	}
	result := append_record(s, .Pending, pledge, pledge.epoch)
	if result.status == .Ready {
		s.view.pending = pledge
		s.view.pending_record_hash = result.receipt
	}
	return result
}

@(private)
load_validated :: proc(s: ^Service) -> ([]u8, bool) {
	history, ok := read_history_bytes()
	if !ok { return nil, false }
	published: Maybe(c.HeadFile)
	if s.view.committed.checkpoint.epoch != 0 { published = s.view.committed }
	view, status := c.validate_custody_history(history, published, s.store)
	return history, (status == .Consistent || status == .Unenrolled) && view == s.view
}

confirm_checkpoint :: proc(s: ^Service, pledge: e.Pledge) -> Result {
	cp := s.view.committed.checkpoint
	if pledge.sequence == cp.sequence {
		history, ok := load_validated(s)
		if !ok { s.fault = true; return {status = .AttestationHistoryFault} }
		for len(history) > 0 {
			n := frame_size(history)
			frame := history[:n]
			history = history[n:]
			if frame[6] != u8(c.FrameKind.Committed) || record_hash(frame) != s.view.committed.committed_record_hash { continue }
			last, err := c.decode_pledge(frame[83:n-32], s.store, cp.epoch)
			if err == .None && last == pledge { return {receipt = s.view.committed.committed_record_hash} }
		}
		return {status = .CheckpointConflict}
	}
	_, valid := load_validated(s)
	if !valid { s.fault = true; return {status = .AttestationHistoryFault} }
	pending, live := s.view.pending.(e.Pledge)
	if !live || e.classify_confirm(pledge, cp, &pending, nil, true) != .EligibleConfirmation {
		return {status = .CheckpointConflict}
	}
	result := append_record(s, .Committed, pledge, cp.epoch)
	if result.status != .Ready { return result }
	head := c.HeadFile{{s.store, cp.epoch, pledge.sequence, pledge.head},result.receipt}
	if !publish_head(head) {
		s.fault = true
		return {status = .CheckpointStorageFault}
	}
	s.view.committed = head
	s.view.pending = nil
	s.view.pending_record_hash = {}
	return result
}

verify_checkpoint :: proc(s: ^Service, cursor: u64) -> Result {
	head, ok, present := read_head_bytes(s.store)
	history, readable := read_history_bytes()
	if !ok || !readable { return {status = .CheckpointStorageFault} }
	view, status := c.validate_custody_history(history, head, s.store)
	#partial switch status {
	case .Consistent:
	case .Unenrolled:
		if present { return {status = .CheckpointInconsistent} }
		return {status = .CheckpointMissing}
	case .CheckpointInconsistent: return {status = .CheckpointInconsistent}
	case .HeadPublicationPending: return {status = .HeadPublicationPending}
	case: return {status = .AttestationHistoryFault}
	}
	if view != s.view { return {status = .AttestationHistoryFault} }
	if cursor > view.ordinal { return {status = .CheckpointConflict} }
	for ordinal := u64(1); len(history) > 0; ordinal += 1 {
		n := frame_size(history)
		if ordinal > cursor && history[6] == u8(c.FrameKind.Rejection) {
			frame: c.RejectionFrameBytes
			copy(frame[:], history[:n])
			return {rejection = frame}
		}
		history = history[n:]
	}
	return {}
}

@(private)
operator_confirmed :: proc(s: ^Service, listener: u64, op: c.Operation, fd: i32) -> (Credentials, bool) {
	peer: Credentials
	ok := wb_peer(fd,&peer) == 0 && c.decide_peer_role(s.roles,listener,u64(peer.uid),op) == .Operator
	return peer, ok
}

// Compare the complete administrative history payload, including the observed UID.
// Only the latest administrative request is eligible for replay.
@(private)
administrative_replay :: proc(history: []u8, kind: c.FrameKind, authorization: e.AuthorizationId, expected: []u8) -> (Result, bool) {
	authorization := authorization
	bytes := history
	seen := false
	replay := false
	receipt: [32]u8
	for len(bytes) > 0 {
		n := frame_size(bytes)
		frame := bytes[:n]
		bytes = bytes[n:]
		offset := 24
		#partial switch c.FrameKind(frame[6]) {
		case .Genesis:
		case .Epoch: offset = 112
		case: continue
		}
		payload := frame[83:n-32]
		replay = frame[6] == u8(kind) && string(payload) == string(expected)
		if replay { receipt = record_hash(frame) }
		if string(payload[offset:offset+16]) == string(authorization[:]) { seen = true }
	}
	if replay { return {receipt = receipt}, true }
	return {status = .CheckpointConflict}, seen
}

enroll_checkpoint :: proc(s: ^Service, req: c.EnrollmentRequest, listener: u64, fd: i32) -> Result {
	peer, allowed := operator_confirmed(s,listener,.Enroll,fd)
	if !allowed { return {status = .CustodianAuthFault} }
	gen := c.Genesis{req.store,req.epoch,req.authorization,req.reason,u64(peer.uid)}
	payload, err := c.encode_genesis(gen,s.store)
	if err != .None { return {status = .Malformed} }
	history, valid := load_validated(s)
	if !valid { s.fault = true; return {status = .AttestationHistoryFault} }
	if replay, known := administrative_replay(history,.Genesis,req.authorization,payload.data[:payload.length]); known { return replay }
	if s.view.committed.checkpoint.epoch != 0 || wb_empty_journal() == 0 { return {status = .CheckpointConflict} }
	hash, _ := c.genesis_head(gen,s.store)
	result := append_record(s,.Genesis,gen,1)
	if result.status != .Ready { return result }
	head := c.HeadFile{{store=s.store,epoch=1,head=hash},result.receipt}
	if !publish_head(head) { s.fault = true; return {status = .CheckpointStorageFault} }
	s.view.committed = head
	return result
}

change_epoch :: proc(s: ^Service, req: c.EpochRequest, listener: u64, fd: i32) -> Result {
	peer, allowed := operator_confirmed(s,listener,.EpochChange,fd)
	if !allowed { return {status = .CustodianAuthFault} }
	change := c.EpochChange{req.old,req.authorization,req.reason,req.unresolved_pending_record_hash,u64(peer.uid)}
	payload, err := c.encode_epoch(change,s.store,req.old.epoch)
	if err != .None { return {status = .Malformed} }
	history, valid := load_validated(s)
	if !valid { s.fault = true; return {status = .AttestationHistoryFault} }
	if replay, known := administrative_replay(history,.Epoch,req.authorization,payload.data[:payload.length]); known { return replay }
	if req.old != s.view.committed.checkpoint || req.unresolved_pending_record_hash != s.view.pending_record_hash {
		return {status = .CheckpointConflict}
	}
	result := append_record(s,.Epoch,change,req.old.epoch)
	if result.status != .Ready { return result }
	next, _ := e.next_epoch(req.old.epoch)
	head := c.HeadFile{{store=s.store,epoch=next},result.receipt}
	copy(head.checkpoint.head[:],payload.data[80:112])
	if !publish_head(head) { s.fault = true; return {status = .CheckpointStorageFault} }
	s.view.committed = head
	s.view.pending = nil
	s.view.pending_record_hash = {}
	return result
}

record_custody_rejection :: proc(s: ^Service, fd: i32, bytes: []u8, complete: bool, status: c.ReplyStatus) -> Result {
	peer: Credentials
	observed := wb_peer(fd,&peer) == 0
	history, ok := load_validated(s)
	if !ok { s.fault = true; return {status = .CheckpointStorageFault} }
	_ = history
	digest, err := c.denial_digest(bytes,u8(complete))
	if err != .None { return {status = .Malformed} }
	epoch := s.view.committed.checkpoint.epoch
	value := c.Rejection{store=s.store,epoch=epoch,fault_code=u16(status),captured_length=u32(len(bytes)),
		request_complete=u8(complete),request_digest=digest,peer_observed=u8(observed),uid=u64(peer.uid),gid=u64(peer.gid),pid=u64(peer.pid)}
	result := append_record(s,.Rejection,value,epoch)
	if result.status == .Ready { result.status = status }
	return result
}
