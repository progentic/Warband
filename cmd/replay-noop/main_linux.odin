package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:encoding/hex"
import "core:encoding/endian"
import "core:crypto/sha2"
import c "../../src/custody"
import e "../../src/domain/events"
import client "../../src/runtime/client"
import store "../../src/store"
import r "../../src/replay"

workspace: [128*1024*1024]u8
show :: proc(label: string,p: r.Projection) {
	p := p
	fmt.println(label,string(hex.encode(p.store[:])),p.epoch,string(hex.encode(p.key.task[:])),string(hex.encode(p.key.run[:])),
	            p.task_version,p.control_revision,p.complete,p.authorization,p.consumed,p.revoked,string(hex.encode(p.attempt[:])),
	            p.observation,p.verdict,p.disposition,p.disposition_reason)
}

main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator = mem.arena_allocator(&arena)
	args := os.args
	if len(args)<6 || (len(args)-6)%2!=0 {
		fmt.eprintln("usage: replay-noop DB SOCKET CUSTODIAN_UID STORE EPOCH [OLD_DB EPOCH_WBCR_HEX]...")
		os.exit(2)
	}
	uid,u := strconv.parse_uint(args[3],10)
	epoch,v := strconv.parse_uint(args[5],10)
	id,b := hex.decode(transmute([]u8)args[4])
	if !strings.has_prefix(args[1],"/") || !strings.has_prefix(args[2],"/") || !u || uid>uint(max(u32)) ||
	   !v || epoch!=uint(1+(len(args)-6)/2) || !b || len(id)!=16 { os.exit(2) }
	start := client.wb_elapsed_ms()
	if start<0 || !store.limit_sqlite() { os.exit(1) }
	s := client.Session{path=strings.clone_to_cstring(args[2]),uid=u32(uid),epoch=e.Epoch(epoch),deadline=start+60_000}
	copy(s.store[:],id)
	fd := client.wb_writer_gate(strings.clone_to_cstring(args[1]))
	if fd<0 { os.exit(1) }
	defer client.wb_release_gate(fd)
	page,ready := client.verify(&s,0)
	if !ready { os.exit(1) }
	cp,first_pending,tip := page.committed,page.pending,page.tip
	receipts: [dynamic]r.Receipt
	for {
		frame,present := page.rejection.(c.RejectionFrameBytes)
		if !present { break }
		cursor,_ := endian.get_u64(frame[11:19],.Little)
		if cursor>tip { break }
		receipt_epoch,_ := endian.get_u64(frame[99:107],.Little)
		ctx: sha2.Context_256
		sha2.init_256(&ctx); sha2.update(&ctx,frame[:])
		rcpt := r.Receipt{epoch=e.Epoch(receipt_epoch)}
		sha2.final(&ctx,rcpt.digest[:])
		if _,err := append(&receipts,rcpt); err!=nil { os.exit(1) }
		page,ready = client.verify(&s,cursor)
		if !ready || page.tip<tip || page.committed!=cp || page.pending!=first_pending { os.exit(1) }
	}
	segments, alloc := make([]r.Segment,int(epoch),context.allocator)
	if alloc!=nil { os.exit(1) }
	live: Maybe(r.Projection)
	for &seg,i in segments {
		path := args[1]
		compare: Maybe(e.Checkpoint)
		if i+1<len(segments) {
			path = args[6+2*i]
			encoded := args[7+2*i]
			if !strings.has_prefix(path,"/") || len(encoded)>2394 { os.exit(2) }
			seg.handoff,b = hex.decode(transmute([]u8)encoded)
			if !b { os.exit(2) }
		} else { compare=cp }
		scope := e.EventRef{s.store,e.Epoch(i+1),0}
		rows,observation,ok := store.read_replay_segment(strings.clone_to_cstring(path),scope,&s,compare)
		if !ok {
			if s.exhausted { fmt.println("Failure ResourceLimit") } else { fmt.println("Failure IntegrityFault") }
			os.exit(1)
		}
		seg.rows = rows
		if observation!=nil { live=observation }
	}
	pending,has := first_pending.(e.Pledge)
	ptr: ^e.Pledge
	if has { ptr = &pending }
	result := r.project(cp,ptr,segments,receipts[:])
	if !client.within_budget(&s) { os.exit(1) }
	if result.error!=.None { fmt.println("Failure",result.error,result.readiness); os.exit(1) }
	fmt.println("Journal",result.readiness,"OutstandingReceipts",len(receipts)-result.receipts_used)
	for task in result.tasks { show("Task",task) }
	if value,ok := live.(r.Projection); ok { show("Live",value) }
}
