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
import "core:strconv"
import l "core:sys/linux"

workspace: [128*1024*1024]u8

review_admission :: proc(live:^r.PreparedProposal,id:[16]u8,start:i64) -> int {
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

// The root setup creates this pair before forking both siblings. It releases
// them only after closing its copies and dropping to the separate courier UID.
normal_workflow :: proc(session:r.RequestSession,example:m.Catalog_Id) -> int {
	control,co:=strconv.parse_int(os.get_env("WB_ISSUER_FD",context.temp_allocator))
	writer,wo:=strconv.parse_int(os.get_env("WB_OPPORTUNITY_FD",context.temp_allocator))
	if !co || !wo || control<3 || writer<3 || control==writer || max(control,writer)>int(max(i32)) { return 1 }
	fd,grant:=l.Fd(control),l.Fd(writer)
	defer l.close(fd)
	defer if grant>=0 { l.close(grant) }
	peer:struct{pid:i32,uid,gid:u32}
	size:=size_of(peer)
	kind:i32
	_,se:=l.getsockopt(fd,1,.TYPE,&kind)
	flags,fe:=l.fcntl(grant,l.F_GETFL)
	st:l.Stat
	parent:=l.getppid()
	if fe!=.NONE || .WRONLY not_in flags || .NONBLOCK not_in flags { return 1 }
	if parent<=1 || se!=.NONE || kind!=5 || l.syscall(l.SYS_getsockopt,fd,1,17,&peer,&size)!=0 ||
	   size!=size_of(peer) || peer.pid!=i32(parent) || peer.uid!=0 || l.fstat(grant,&st)!=.NONE || !l.S_ISFIFO(st.mode) ||
	   l.prctl(4,0,0,0,0)!=.NONE || l.prctl(1,uint(l.Signal.SIGKILL),0,0,0)!=.NONE || l.getppid()!=parent { return 1 }

	start:=client.wb_elapsed_ms()
	if start<0 { return 1 }
	issued:a.RequestIssued
	status,id:=r.request_round(session,.Issue,example,issuance=&issued)
	if status!=.Issued { fmt.println(status); return 1 }
	frame:[52]u8
	copy(frame[:4],"WBT1")
	copy(frame[4:36],hex.encode(id[:]))
	endian.put_u32(frame[36:40],.Little,issued.revision)
	endian.put_u32(frame[40:44],.Little,issued.catalog_id)
	endian.put_u64(frame[44:],.Little,issued.deadline_ms)
	if n,err:=l.write(grant,frame[:]); err!=.NONE || n!=len(frame) { return 1 }
	l.close(grant)
	grant=-1
	if n,err:=l.send(fd,frame[:],{.NOSIGNAL,.DONTWAIT}); err!=.NONE || n!=len(frame) { return 1 }
	now:=client.wb_elapsed_ms()
	if now<start || u64(now)>=issued.deadline_ms { fmt.println("Deadline"); return 1 }
	fds:=[1]l.Poll_Fd{{fd=fd,events={.IN}}}
	ready,wait:=l.poll(fds[:],i32(issued.deadline_ms-u64(now)))
	if wait!=.NONE || ready!=1 { fmt.println("OutcomeUncertain"); return 1 }
	buf:[160]byte
	vec:=[1]l.IO_Vec{{&buf[0],len(buf)}}
	msg:=l.Msg_Hdr{iov=vec[:]}
	n,err:=l.recvmsg(fd,&msg,{.DONTWAIT})
	if err!=.NONE || n<=0 || .CTRUNC in msg.flags || .TRUNC in msg.flags { fmt.println("OutcomeUncertain"); return 1 }
	input:=m.ProjectionInput{revision=issued.revision,example=m.Catalog_Id(issued.catalog_id)}
	copy(input.id[:],frame[4:36])
	reply,valid:=m.decode_provider_reply(buf[:n],input)
	if !valid { fmt.println("InvalidHandoff"); return 1 }
	selected,ok:=reply.outcome.(m.Validated_Candidate)
	if !ok {
		if counts,observed:=reply.counts.(m.TransferCounts); observed {
			fmt.println("ProviderFailure",reply.outcome,"Observed",counts.http_status,counts.uploaded,counts.headers,counts.received)
		} else {
			fmt.println("ProviderFailure",reply.outcome,"CountsUnavailable")
		}
		return 1
	}
	prepared:=r.PreparedProposal{directory_fd=-1}
	defer if prepared.directory_fd>=0 { l.close(prepared.directory_fd) }
	status,_=r.request_round(session,.AdmitSelection,id=id,selection=selected,review=&prepared)
	fmt.println(status)
	if status!=.Admitted { return 1 }
	return review_admission(&prepared,id,start)
}

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
			return review_admission(live,id,start)
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
	case "handoff-empty","handoff-abc":
		return normal_workflow(session,1 if os.args[1]=="handoff-empty" else 2)
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
