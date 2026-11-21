package custody_client

import c "../../custody"
import e "../../domain/events"

foreign import native "system:wb_runtime_client"
foreign native {
	wb_writer_gate :: proc(path: cstring) -> i32 ---
	wb_release_gate :: proc(fd: i32) ---
	wb_elapsed_ms :: proc() -> i64 ---
	wb_recorded_us :: proc() -> i64 ---
	wb_exchange :: proc(path: cstring, uid: u32, data: rawptr, size: i32, reply: rawptr, cap: i32, deadline: i64) -> i32 ---
}

Session :: struct {path: cstring, uid: u32, store: e.StoreId, epoch: e.Epoch, deadline: i64, visits: u64, exhausted: bool}
within_budget :: proc(s: ^Session, visits: u64 = 0) -> bool {
	now := wb_elapsed_ms()
	if now < s.deadline-60_000 || now >= s.deadline || visits > 100_000-s.visits { s.exhausted = true }
	if s.exhausted { return false }
	s.visits += visits
	return true
}

exchange :: proc(s: ^Session, req: c.Request, deadline: i64) -> (c.Reply, bool) {
	if req.operation != .Verify && req.operation != .Prepare && req.operation != .Confirm { return {}, false }
	if !within_budget(s) { return {}, false }
	wire, err := c.encode_request(req,s.store,s.epoch)
	if err != .None { return {}, false }
	hash, digest_err := c.digest_request(req,s.store,s.epoch)
	if digest_err != .None { return {}, false }
	cursor: u64
	if v, ok := req.payload.(c.VerifyRequest); ok { cursor = v.after_ordinal }
	ctx := c.ReplyContext{true,req.operation,hash,s.store,s.epoch,cursor}
	bytes: [491]u8 // one byte beyond the largest legal reply
	start := wb_elapsed_ms()
	if start < 0 { return {}, false }
	end := min(deadline,s.deadline,start+30_000)
	n := wb_exchange(s.path,s.uid,&wire.data,i32(wire.length),&bytes,len(bytes),end)
	now := wb_elapsed_ms()
	if !within_budget(s) || n < 0 || now < start || now >= end { return {}, false }
	reply, reply_err := c.decode_reply(bytes[:n],ctx)
	if reply_err != .None || reply.status != .Ready { return {}, false }
	// verify validates the whole custody history then walks it for the earliest receipt.
	// Charge a conservative two passes, including repeated requests and replay scans.
	if reply.tip > 100_000 { s.exhausted = true; return {},false }
	return reply, within_budget(s,2*reply.tip+1)
}

verify :: proc(s: ^Session, cursor: u64) -> (c.Reply, bool) {
	return exchange(s,{.Verify,c.VerifyRequest{s.store,s.epoch,cursor}},s.deadline)
}
