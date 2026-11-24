package main

import r "../../src/runtime"
import client "../../src/runtime/client"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import l "core:sys/linux"

workspace: [128*1024*1024]u8

run :: proc() -> int {
	if len(os.args)!=2 { return 2 }
	session,ok:=r.open_request_session()
	if !ok { fmt.println("Unavailable"); return 1 }
	defer l.close(session.lease)
	switch os.args[1] {
	case "provision","recover":
		op:=r.RequestOperation.Provision
		if os.args[1]=="recover" { op=.Recover }
		for i:=0;i<35;i+=1 {
			temp:=mem.begin_arena_temp_memory(cast(^mem.Arena)context.allocator.data)
			status,_:=r.request_round(session,op)
			mem.end_arena_temp_memory(temp)
			fmt.println(status)
			if status==.Ready { return 0 }
			if op!=.Recover || (status!=.Recorded && status!=.Expired) { return 1 }
		}
	case "retry":
		input:[32+8192+1]u8
		n:=client.read_payload(input[:])
		if n<32 || n>=len(input) { return 2 }
		bytes,valid:=hex.decode(input[:32])
		if !valid || len(bytes)!=16 { return 2 }
		id:[16]u8
		copy(id[:],bytes)
		status,_:=r.request_round(session,.Admit,id=id,candidate=input[32:n])
		fmt.println(status)
		return 0 if status==.Admitted else 1
	case "issue-empty","issue-abc":
		status,id:=r.request_round(session,.Issue,1 if os.args[1]=="issue-empty" else 2)
		if status!=.Issued { fmt.println(status); return 1 }
		fmt.println(status,string(hex.encode(id[:])))
		// An explicit local fixture input cancels. EOF drops the live session.
		fds:=[?]l.Poll_Fd{{fd=0,events={.IN}}}
		ready,wait:=l.poll(fds[:],30_000)
		if wait!=.NONE { return 1 }
		if ready==0 {
			status,_=r.request_round(session,.ExpireDue,id=id)
			fmt.println(status)
			return 0 if status==.Expired else 1
		}
		b:[1]u8
		n,err:=l.read(0,b[:])
		if err!=.NONE || n!=1 { return 1 }
		if b[0]=='a' || (b[0]=='r' && #config(WARBAND_REQUEST_PROOF,false)) {
			input:[8193]u8
			count:=client.read_payload(input[:])
			if count<0 || count==len(input) { return 1 }
			when #config(WARBAND_REQUEST_PROOF,false) {
				if b[0]=='r' {
					child,failed:=l.fork()
					if failed!=.NONE { return 1 }
					status,_=r.request_round(session,.Admit,id=id,candidate=input[:count])
					fmt.println(status)
					if child==0 { l.exit_group(0) }
					code:u32
					_,we:=l.wait4(child,&code,{},nil)
					return 0 if we==.NONE && code==0 else 1
				}
			}
			status,_=r.request_round(session,.Admit,id=id,candidate=input[:count])
			fmt.println(status)
			return 0 if status==.Admitted else 1
		}
		if b[0]!='c' { return 1 }
		status,_=r.request_round(session,.Cancel,id=id)
		fmt.println(status)
		return 0 if status==.Expired else 1
	}
	return 2
}
main :: proc() {
	arena:mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator=mem.arena_allocator(&arena)
	os.exit(run())
}
