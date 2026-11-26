package main

import "core:os"
import "core:strconv"
import "core:mem"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:crypto/sha2"
import "core:strings"
import c "../../src/custody"
import svc "../../src/custody/linux"
import e "../../src/domain/events"

workspace: [8*1024*1024]u8

main :: proc() {
	args := os.args
	if len(args) != 5 { os.exit(2) }
	runtime_uid, runtime_ok := strconv.parse_uint(args[2],10)
	operator_uid, operator_ok := strconv.parse_uint(args[3],10)
	if !runtime_ok || !operator_ok || runtime_uid > uint(max(u32)) || operator_uid > uint(max(u32)) || len(args[4]) != 32 { os.exit(2) }
	store_text: [32]u8
	copy(store_text[:],args[4])
	store_bytes, hex_ok := hex.decode(store_text[:])
	if !hex_ok { os.exit(2) }
	s: svc.Service
	copy(s.store[:],store_bytes)
	delete(store_bytes)
	empty_store := e.StoreId{}
	if s.store == empty_store { os.exit(2) }
	name := strings.clone_to_cstring(args[1])
	lock_result := svc.wb_lock(name,u32(runtime_uid),u32(operator_uid))
	delete(name)
	if lock_result != 0 { os.exit(3) }
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator = mem.arena_allocator(&arena)
	if !svc.recover_checkpoint(&s) { os.exit(4) }
	a := svc.wb_listen(0)
	if a < 0 { os.exit(5) }
	b := svc.wb_listen(1)
	if b < 0 { os.exit(5) }
	operators := [1]u64{u64(operator_uid)}
	s.roles = {u64(a),u64(b),u64(runtime_uid),operators[:]}
	serve_loop(&s, &arena, a, b)
	svc.wb_close(b)
	svc.wb_close(a)
	svc.wb_unlock()
	os.exit(6)
}

serve_loop :: proc(s: ^svc.Service, arena: ^mem.Arena, runtime, admin: i32) {
	for !s.fault {
		mem.arena_free_all(arena)
		listener := svc.wb_wait(runtime,admin)
		if listener < 0 { return }
		serve_request(s,arena,listener)
	}
}

serve_request :: proc(s: ^svc.Service, arena: ^mem.Arena, listener: i32) {
	fd := svc.wb_accept(listener)
	if fd < 0 { return }
	defer svc.wb_close(fd)
	peer: svc.Credentials
	uid: Maybe(u64)
	if svc.wb_peer(fd,&peer) == 0 { uid = u64(peer.uid) }
	start := svc.wb_millis()
	if start < 0 { return }
	deadline := start+30_000
	buffer: [65547]u8
	complete: i32
	n := svc.wb_request(fd,&buffer,len(buffer),&complete,deadline)
	raw := buffer[:n]
	op := c.Operation(0)
	if n > 6 { op = c.Operation(raw[6]) }
	role := c.decide_peer_role(s.roles,u64(listener),uid,op)
	epoch := s.view.committed.checkpoint.epoch
	request_epoch := epoch
	// Epoch replay may refer to the preceding epoch. change_epoch validates the actual old checkpoint.
	if op == .EpochChange && n >= 35 {
		word, _ := endian.get_u64(raw[27:35],.Little)
		request_epoch = e.Epoch(word)
	}
	req, err := c.decode_request(raw,s.store,request_epoch)
	result: svc.Result
	cursor: u64
	received := svc.wb_millis()
	if role == .Denied {
		result.status = .CustodianAuthFault
	} else if complete == 0 || err != .None {
		result.status = .Malformed
		if err == .Unsupported { result.status = .Unsupported }
	} else if received < start || received >= deadline {
		result.status = .AttestationUncertain
	} else {
		switch op {
		case .Prepare: result = svc.prepare_checkpoint(s,req.payload.(e.Pledge))
		case .Confirm: result = svc.confirm_checkpoint(s,req.payload.(e.Pledge))
		case .Verify:
			cursor = req.payload.(c.VerifyRequest).after_ordinal
			result = svc.verify_checkpoint(s,cursor)
		case .Enroll: result = svc.enroll_checkpoint(s,req.payload.(c.EnrollmentRequest),u64(listener),fd)
		case .EpochChange: result = svc.change_epoch(s,req.payload.(c.EpochRequest),u64(listener),fd)
		}
	}
	if result.status != .Ready && !s.fault {
		// A diagnostic from an authenticated read-only verify never repairs or mutates custody.
		if !(op == .Verify && role == .Runtime && err == .None && complete != 0 && result.status != .CheckpointConflict) {
			mem.arena_free_all(arena)
			result = svc.record_custody_rejection(s,fd,raw,complete != 0,result.status)
		}
	}
	// An incomplete or unknown operation has no valid WBRS correlation.
	if complete == 0 || u8(op) < 1 || u8(op) > 5 { return }
	now := svc.wb_millis()
	if now < received || now >= deadline { s.fault = true; return }
	ctx := c.ReplyContext{authenticated = role != .Denied && result.status != .CustodianAuthFault,
		operation=op,request_digest=request_hash(raw),store=s.store,epoch=s.view.committed.checkpoint.epoch,after_ordinal=cursor}
	reply := c.Reply{status=result.status,receipt=result.receipt,committed=s.view.committed.checkpoint,
		pending=s.view.pending,tip=s.view.ordinal,rejection=result.rejection}
	wire, reply_error := c.encode_reply(reply,ctx)
	if reply_error == .None { _ = svc.wb_reply(fd,&wire.data,uintptr(wire.length),deadline) }
}

request_hash :: proc(bytes: []u8) -> [32]u8 {
	prefix: [len("warband.request.v1\x00")]u8
	copy(prefix[:],"warband.request.v1\x00")
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx,prefix[:])
	sha2.update(&ctx,bytes)
	hash: [32]u8
	sha2.final(&ctx,hash[:])
	return hash
}
