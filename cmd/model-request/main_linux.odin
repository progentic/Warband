package main

import a "../../src/audit"
import m "../../src/model"
import "core:encoding/endian"
import r "../../src/runtime"
import client "../../src/runtime/client"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import l "core:sys/linux"

workspace: [128*1024*1024]u8

// The offline driver owns a private sequenced-packet channel to the live issuer.
workflow_fixture :: proc(session:r.RequestSession, example:m.Catalog_Id, operator_review:=false) -> int {
	start:=client.wb_elapsed_ms()
	if start<0 { return 1 }
	issued: a.RequestIssued
	status,id:=r.request_round(session,.Issue,example,issuance=&issued)
	if status!=.Issued { fmt.println(status); return 1 }
	fmt.println(status,string(hex.encode(id[:])),issued.revision,issued.catalog_id,issued.deadline_ms)
	for delivery in 0..<2 {
		fds:=[?]l.Poll_Fd{{fd=0,events={.IN}}}
		ready,wait:=l.poll(fds[:],35_000)
		if wait!=.NONE || ready!=1 { return 1 }
		packet:[41]u8 // One spare byte detects oversized selection records.
		n,err:=l.read(0,packet[:])
		if err!=.NONE { return 1 }
		if n==0 && delivery==1 { return 0 }
		if n!=40 { return 1 }
		selected:m.Validated_Candidate
		copy(selected.request_id[:],packet[:32])
		catalog,_:=endian.get_u32(packet[32:36],.Little)
		length,_:=endian.get_u32(packet[36:40],.Little)
		selected.example=m.Catalog_Id(catalog)
		selected.decoded_length=int(length)
		prepared:=r.PreparedProposal{directory_fd=-1}
		live:^r.PreparedProposal
		if operator_review { live=&prepared }
		defer if prepared.directory_fd>=0 { l.close(prepared.directory_fd) }
		status,_=r.request_round(session,.AdmitSelection,id=id,selection=selected,review=live)
		fmt.println(status)
		if status!=.Admitted { return 1 }
		if operator_review {
			peer:u32
			sock:=client.wb_approval_socket(1,&peer)
			if sock<0 { return 1 }
			defer l.close(l.Fd(sock))
			fmt.println("AwaitingOperator")
			fd:=client.wb_approval_accept(sock,peer,start+180_000)
			if fd<0 { return 1 }
			defer l.close(l.Fd(fd))
			result:=r.marker_review(fd,peer,live,start,cast(^mem.Arena)context.allocator.data,id)
			fmt.println(result.status)
			return 0 if result.status==.Permitted || result.status==.Rejected else 1
		}
	}
	return 0
}

run :: proc() -> int {
	if len(os.args)!=2 { return 2 }
	session,ok:=r.open_request_session()
	if !ok { fmt.println("Unavailable"); return 1 }
	defer l.close(session.lease)
	when #config(WARBAND_REQUEST_PROOF,false) {
		switch os.args[1] {
		case "workflow-review-empty": return workflow_fixture(session,1,true)
		case "workflow-review-abc": return workflow_fixture(session,2,true)
		case "workflow-empty": return workflow_fixture(session,1)
		case "workflow-abc": return workflow_fixture(session,2)
		}
	}
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
