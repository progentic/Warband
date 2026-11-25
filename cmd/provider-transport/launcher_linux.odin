package main

import c "core:c"
import curl "vendor:curl"
import "core:encoding/endian"
import "core:os"
import "core:fmt"
import l "core:sys/linux"
import m "../../src/model"

// The fixture's trusted bootstrap starts as root with three inherited handles.
// The issuer grants one spawn via an anonymous pipe containing exactly one tuple.
// Reading that PIPE_BUF-sized tuple spends it before fork, including on errors.
roles :: enum {Transport, Frontend}
lock_fds :: proc(allowed:[]l.Fd) -> bool {
	first:=l.Fd(3)
	for {
		next:=l.Fd(max(i32))
		for fd in allowed { if fd>=first && fd<next { next=fd } }
		if first<next && l.close_range(first,next-1,{})!=.NONE { return false }
		if next==l.Fd(max(i32)) { return true }
		first=next+1
	}
	return false
}

isolate :: proc(role:roles,parent:l.Pid,allowed:[]l.Fd) -> bool {
	if !lock_fds(allowed) { return false }
	uid:=l.Uid(60001)
	if role==.Frontend {
		uid=60002
		if l.syscall(l.SYS_unshare,0x40000000)!=0 { return false } // CLONE_NEWNET
	}
	return l.setgroups(nil)==.NONE && l.setresgid(l.Gid(uid),l.Gid(uid),uid)==.NONE &&
	       l.setresuid(uid,uid,uid)==.NONE && l.prctl(4,0,0,0,0)==.NONE &&
	       l.prctl(38,1,0,0,0)==.NONE && l.prctl(1,uint(l.Signal.SIGKILL),0,0,0)==.NONE && l.getppid()==parent
}

peer_is_parent :: proc(control:l.Fd,parent:l.Pid) -> bool {
	creds:struct {pid:i32,uid,gid:u32}
	size:=size_of(creds)
	kind:i32
	_,err:=l.getsockopt(control,1,.TYPE,&kind)
	return err==.NONE && kind==5 && l.syscall(l.SYS_getsockopt,control,1,17,&creds,&size)==0 &&
	       size==size_of(creds) && creds.pid==i32(parent) && creds.uid==0
}

input_for :: proc(frame:Frame) -> (input:m.ProjectionInput) {
	frame:=frame
	copy(input.id[:],frame[4:36])
	input.revision,_=endian.get_u32(frame[36:40],.Little)
	example,_:=endian.get_u32(frame[40:44],.Little)
	input.example=m.Catalog_Id(example)
	return
}

run_transport :: proc(control,secret,output:l.Fd,frame:Frame,start,deadline:i64) -> bool {
	t:=Transfer{frame=frame,socket=-1,control=control,deadline=deadline,setup_end=min(deadline,start+5000)}
	result:="ProfileUnavailable"
	if curl.global_init(c.long(curl.GLOBAL_DEFAULT))==.E_OK {
		result=transfer(&t,frame,input_for(frame),secret)
		curl.global_cleanup()
	}
	packet:[32+m.ResponseBodyLimit+32]byte
	endian.put_u32(packet[0:4],.Little,u32(t.status))
	endian.put_u32(packet[4:8],.Little,u32(t.sent))
	endian.put_u32(packet[8:12],.Little,u32(t.header_bytes))
	endian.put_u32(packet[12:16],.Little,u32(t.used))
	n:=16+copy(packet[16:],result)+1
	if result=="Ok" { n+=copy(packet[n:],t.response[:t.used]) }
	return send(output,packet[:n])
}

run_front :: proc(input_fd,output:l.Fd,frame:Frame,deadline:i64) -> bool {
	packet:[64+m.ResponseBodyLimit]byte
	if !readable(input_fd,deadline+1000) { return false }
	n,other:=receive(input_fd,packet[:])
	if n<=17 || other>=0 { return false }
	i:=16
	for i<n && packet[i]!=0 { i+=1 }
	if i==n { return false }
	result:=string(packet[16:i])
	variant:m.ChatValidation
	if result=="Ok" {
		variant=m.validate_chat_completion(packet[i+1:n],input_for(frame))
		switch v in variant {
		case m.Validated_Candidate:
			// Return only the validated selection and a fixture-only content digest.
			digest:=m.catalog_digest(string(packet[i+1:n]))
			n=i+1+copy(packet[i+1:],digest[:])
			rid:=v.request_id
			n+=copy(packet[n:],rid[:])
			endian.put_u32(packet[n:n+4],.Little,u32(v.example))
			endian.put_u32(packet[n+4:n+8],.Little,u32(v.decoded_length))
			n+=8
		case m.Candidate_Rejection: n=16+copy(packet[16:],fmt.tprintf("Candidate.%v",v))
		case m.ProfileStatus: n=16+copy(packet[16:],fmt.tprintf("Envelope.%v",v))
		}
	} else { n=i }
	return send(output,packet[:n])
}

kill_and_reap :: proc(slot:^l.Pid) {
	pid:=slot^
	if pid<=0 { return }
	slot^ = -1
	_=l.kill(pid,.SIGKILL)
	status:u32
	for {
		_,e:=l.wait4(pid,&status,{},nil)
		if e!=.EINTR { break }
	}
}

launch :: proc() -> int {
	// Only the explicit IPC and grant handles cross the bootstrap boundary.
	null,ne:=l.open("/dev/null",{.RDWR,.NOFOLLOW,.CLOEXEC})
	if ne!=.NONE || null<3 { return 1 }
	for std in 0..<3 {
		if _,err:=l.dup3(null,l.Fd(std),{}); err!=.NONE { return 1 }
	}
	l.close(null)
	control,secret,grant:=env_fd("WB_ISSUER_FD"),env_fd("WB_CREDENTIAL_FD"),env_fd("WB_OPPORTUNITY_FD")
	os.clear_env()
	if control<3 || grant<3 || control==secret || control==grant || secret==grant { return 1 }
	parent:=l.getppid()
	if !lock_fds(([]l.Fd{control,secret,grant})) || !peer_is_parent(control,parent) ||
	   l.setrlimit(.CORE,&l.RLimit{})!=.NONE || l.prctl(4,0,0,0,0)!=.NONE ||
	   l.prctl(1,uint(l.Signal.SIGKILL),0,0,0)!=.NONE || l.getppid()!=parent { return 1 }
	start:=now_ms()
	frame,witness:Frame
	if start<0 || !readable(control,start+5000) { return 1 }
	n,other:=receive(control,frame[:])
	if n!=len(frame) || other>=0 || string(frame[:4])!="WBT1" {
		_=send(control,transmute([]byte)string("InvalidHandoff")); return 0
	}
	if secret<3 { _=send(control,transmute([]byte)string("CredentialUnavailable")); return 0 }
	st:l.Stat
	if l.fstat(grant,&st)!=.NONE || !l.S_ISFIFO(st.mode) || !readable(grant,start+5000) { return 1 }
	got_grant,e:=l.read(grant,witness[:])
	l.close(grant)
	if e!=.NONE || got_grant!=len(frame) || witness!=frame {
		_=send(control,transmute([]byte)string("Spent")); return 0
	}
	until,_:=endian.get_u64(frame[44:],.Little)
	deadline:=i64(min(until,u64(start+30_000)))
	if now_ms()>=deadline { _=send(control,transmute([]byte)string("Deadline")); return 0 }
	result,ingress,handoff:[2]l.Fd
	for pair in ([?]^[2]l.Fd{&result,&ingress,&handoff}) {
		if l.socketpair(.LOCAL,.SEQPACKET,l.Protocol(0),pair)!=.NONE { return 1 }
	}
	me:=l.getpid()
	worker,ce:=l.fork()
	if ce!=.NONE { return 1 }
	if worker==0 {
		if !isolate(.Transport,me,([]l.Fd{control,secret,ingress[0],handoff[0]})) ||
		   !peer_is_parent(handoff[0],me) || !readable(handoff[0],deadline) { l.exit_group(1) }
		got:Frame
		count,fd:=receive(handoff[0],got[:])
		l.close(handoff[0])
		if count!=len(frame) || fd>=0 || got!=frame { l.exit_group(1) }
		l.exit_group(0 if run_transport(control,secret,ingress[0],got,start,deadline) else 1)
	}
	defer kill_and_reap(&worker)
	l.close(secret) // Before fork of the front end; plaintext exists only in the transport.
	l.close(ingress[0]); l.close(handoff[0])
	front,fe:=l.fork()
	if fe!=.NONE { return 1 }
	if front==0 {
		ok:=isolate(.Frontend,me,([]l.Fd{ingress[1],result[1]}))
		l.exit_group(0 if ok && run_front(ingress[1],result[1],frame,deadline) else 1)
	}
	defer kill_and_reap(&front)
	l.close(result[1]); l.close(ingress[1])
	if !send(handoff[1],frame[:]) { return 1 }
	l.close(handoff[1])
	packet:[160]byte
	for {
		f:=[2]l.Poll_Fd{{fd=result[0],events={.IN}},{fd=control,events={.RDHUP}}}
		ready,err:=l.poll(f[:],i32(clamp(deadline-now_ms(),0,100)))
		if err!=.NONE || .HUP in f[1].revents || .RDHUP in f[1].revents { return 1 }
		if ready>0 && .IN in f[0].revents {
			count,fd:=receive(result[0],packet[:])
			if fd>=0 || count<17 { return 1 }
			if string(packet[16:19])=="Ok\x00" && now_ms()>=deadline { break }
			kill_and_reap(&worker); kill_and_reap(&front)
			return 0 if send(control,packet[:count]) else 1
		}
		if .HUP in f[0].revents { return 1 }
		if now_ms()>=deadline { break }
	}
	kill_and_reap(&worker); kill_and_reap(&front)
	_=send(control,transmute([]byte)string("Deadline"))
	return 0
}
