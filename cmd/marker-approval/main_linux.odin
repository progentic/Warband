package main

import a "../../src/audit"
import e "../../src/domain/events"
import r "../../src/runtime"
import c "../../src/runtime/client"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import l "core:sys/linux"

workspace: [128*1024*1024]u8
operator_cli :: proc(fd: i32,runtime: u32,deadline: i64) -> int {
	actual: u32
	if c.wb_approval_peer(fd,runtime,&actual)!=0 { return 1 }
	wire: a.MarkerProposalEncoding
	n := c.wb_approval_packet(fd,&wire.data,len(wire.data),0,deadline)
	if n<88 || n>len(wire.data) { return 1 }
	store: e.StoreId
	copy(store[:],wire.data[8:24])
	epoch,_ := endian.get_u64(wire.data[24:32],.Little)
	p,err := a.decode_marker_proposal(wire.data[:n],store,e.Epoch(epoch))
	if err!=.None { return 1 }
	f,h,issue := a.marker_proposal_hashes(p,store,e.Epoch(epoch))
	if issue!=.None { return 1 }
	fmt.println("Proposal",string(hex.encode(store[:])),epoch,p.reference.sequence)
	fmt.println("Task",string(hex.encode(p.task[:])),"Run",string(hex.encode(p.run[:])),
	            "ProposalID",string(hex.encode(p.proposal[:])),"Attempt",string(hex.encode(p.attempt[:])))
	fmt.println("Create marker in private directory",string(hex.encode(p.directory[:])),"device",p.device,"inode",p.inode)
	fmt.println("Versions",p.expected_task_version,p.expected_control_revision,"policy 2; criterion approved marker; recovery stop/reconcile")
	fmt.println("Fingerprint",string(hex.encode(f[:])),"Length",p.length,"SHA256",string(hex.encode(h[:])))
	fmt.println("Type approve or reject and press Enter.")
	line: [8]u8
	used := 0
	for used<len(line) {
		now := c.wb_elapsed_ms()
		if now<0 || now>=deadline { return 1 }
		fds := [?]l.Poll_Fd{{fd=0,events={.IN}}}
		ready,wait := l.poll(fds[:],i32(deadline-now))
		if wait!=.NONE || ready!=1 { return 1 }
		count,re := l.read(0,line[used:used+1])
		if re!=.NONE || count!=1 { return 1 }
		used+=1
		if line[used-1]=='\n' { break }
	}
	decision: a.MarkerDecision
	switch string(line[:used]) {
	case "approve\n": decision=.Approve
	case "reject\n": decision=.Reject
	case: return 1
	}
	packet,ok := r.decision_packet(p,decision)
	if !ok || c.wb_approval_packet(fd,&packet,len(packet),1,deadline)!=len(packet) { return 1 }
	reply: [33]u8
	if c.wb_approval_packet(fd,&reply,len(reply),0,deadline)!=len(reply) { fmt.println("OutcomeUncertain"); return 1 }
	status := r.ReviewStatus(reply[0])
	if status!=.Permitted && status!=.Rejected && status!=.Recorded { fmt.println(status); return 1 }
	ep,_ := endian.get_u64(reply[17:25],.Little)
	seq,_ := endian.get_u64(reply[25:],.Little)
	if string(reply[1:17])!=string(store[:]) || ep!=epoch || seq<=u64(p.reference.sequence) { return 1 }
	fmt.println(status,string(hex.encode(reply[1:17])),ep,seq)
	return 0
}

run :: proc(arena: ^mem.Arena) -> int {
	if len(os.args)!=2 { return 2 }
	mode := os.args[1]
	if mode!="decide" && mode!="serve" && mode!="receipts" { return 2 }
	start := c.wb_elapsed_ms()
	if start<0 { return 1 }
	peer: u32
	sock := c.wb_approval_socket(i32(mode!="decide"),&peer)
	if sock<0 { return 1 }
	defer l.close(l.Fd(sock))
	if mode=="decide" { return operator_cli(sock,peer,start+180_000) }
	prepared: r.PreparedProposal
	live: ^r.PreparedProposal
	if mode=="serve" {
		buf: [a.MarkerPayloadLimit+1]u8
		n := c.read_payload(buf[:])
		if n<0 || n>a.MarkerPayloadLimit { return 1 }
		status: r.IntakeOutcome
		prepared,status=r.marker_intake(buf[:n],arena)
		if status!=.ConfirmedProposal { fmt.println(status); return 1 }
		live=&prepared
	}
	defer if live!=nil { l.close(live.directory_fd) }
	if mode=="receipts" {
		task,control,ok := r.marker_review_versions(peer,start,arena)
		if !ok { return 1 }
		fmt.println("ConfirmedProjection",task,control)
	}
	fmt.println("AwaitingOperator")
	fd := c.wb_approval_accept(sock,peer,start+180_000)
	if fd<0 { return 1 }
	defer l.close(l.Fd(fd))
	result := r.marker_review(fd,peer,live,start,arena)
	fmt.println(result.status,"LiveGrant",result.grant!=nil)
	return 0 if result.status==.Permitted || result.status==.Rejected || result.status==.Recorded else 1
}
main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator=mem.arena_allocator(&arena)
	os.exit(run(&arena))
}
