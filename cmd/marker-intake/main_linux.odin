package main

import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import l "core:sys/linux"
import a "../../src/audit"
import r "../../src/runtime"
import c "../../src/runtime/client"

workspace: [128*1024*1024]u8
run :: proc(scratch: ^mem.Arena) -> int {
	if len(os.args)!=1 { fmt.eprintln("usage: marker-intake < payload"); return 2 }
	buf: [a.MarkerPayloadLimit+1]u8
	size := 0
	start := c.wb_elapsed_ms()
	for size<len(buf) {
		now := c.wb_elapsed_ms()
		if start<0 || now<start || now-start>=30_000 { return 1 }
		poll := [?]l.Poll_Fd{{fd=0,events={.IN}}}
		ready,wait := l.poll(poll[:],i32(30_000-(now-start)))
		if wait!=.NONE || ready!=1 { return 1 }
		n,err := l.read(0,buf[size:])
		if err!=.NONE { return 1 }
		if n==0 { break }
		size+=n
	}
	if size>a.MarkerPayloadLimit { fmt.println("PayloadTooLarge"); return 1 }
	prepared,status := r.marker_intake(buf[:size],scratch)
	if status!=.ConfirmedProposal {
		fmt.println(status)
		return 0 if status==.RecoveredConfirmation else 1
	}
	defer l.close(prepared.directory_fd)
	p := &prepared.proposal
	fp,digest,err := a.marker_proposal_hashes(p^,p.reference.store,p.reference.epoch)
	if err!=.None { return 1 }
	when #config(WARBAND_INTAKE_STOP,0)==3 {
		if l.kill(l.getpid(),.SIGSTOP)!=.NONE { return 1 }
	}
	fmt.println(status,string(hex.encode(p.reference.store[:])),p.reference.epoch,p.reference.sequence,
	            string(hex.encode(fp[:])),p.length,string(hex.encode(digest[:])),prepared.projection.task_version,prepared.projection.control_revision)
	return 0
}
main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator=mem.arena_allocator(&arena)
	os.exit(run(&arena))
}
