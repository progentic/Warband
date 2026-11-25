package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import l "core:sys/linux"
import curl "vendor:curl"
import m "../../src/model"

Frame :: [52]byte
env_fd :: proc(name:string) -> l.Fd {
	s:=os.get_env(name,context.temp_allocator)
	v,ok:=strconv.parse_int(s)
	return l.Fd(v) if ok && v>=3 && v<=int(max(i32)) else -1
}

send :: proc(fd:l.Fd,data:[]byte) -> bool {
	n,e:=l.send(fd,data,{.NOSIGNAL,.DONTWAIT})
	return e==.NONE && n==len(data)
}

readable :: proc(fd:l.Fd,until:i64) -> bool {
	p:=[1]l.Poll_Fd{{fd=fd,events={.IN}}}
	left:=until-now_ms()
	if left<=0 { return false }
	n,e:=l.poll(p[:],i32(min(left,30_000)))
	return e==.NONE && n==1
}

// Use recvmsg even for the tuple: unexpected ancillary data must be visible.
receive :: proc "contextless" (fd:l.Fd,buf:[]byte) -> (int,l.Fd) {
	control:[3]u64
	vec:=[1]l.IO_Vec{{raw_data(buf),uint(len(buf))}}
	msg:=l.Msg_Hdr{iov=vec[:],control=(cast(^[24]byte)&control)[:]}
	n,e:=l.recvmsg(fd,&msg,{.CMSG_CLOEXEC,.DONTWAIT})
	if e!=.NONE || .CTRUNC in msg.flags || .TRUNC in msg.flags { return -1,-1 }
	if len(msg.control)==0 { return n,-1 }
	if len(msg.control)!=24 || control[0]!=20 || control[1]!=(u64(1)<<32|1) { return -1,-1 }
	return n,l.Fd(u32(control[2]))
}

credential :: proc(fd:l.Fd,header:[]byte) -> bool {
	st:l.Stat
	seals,e:=l.fcntl(fd,l.F_GET_SEALS)
	if e!=.NONE || !(l.Seal{.WRITE,.GROW,.SHRINK,.SEAL} <= seals) || l.fstat(fd,&st)!=.NONE ||
	   !l.S_ISREG(st.mode) || st.nlink!=0 || st.size<=0 || st.size>1024 { return false }
	path:=fmt.ctprintf("/proc/self/fd/%d",fd)
	name:[128]byte
	size,linkerr:=l.readlink(path,name[:])
	if linkerr!=.NONE || size<=0 || !strings.has_prefix(string(name[:size]),"/memfd:") { return false }
	at:=copy(header,"Authorization: Bearer ")
	n,err:=l.pread(fd,header[at:at+int(st.size)],0)
	if err!=.NONE || n!=int(st.size) { return false }
	padding:=false
	for ch in header[at:at+n] {
		if ch=='=' { padding=true; continue }
		if padding || !(ch>='a' && ch<='z' || ch>='A' && ch<='Z' || ch>='0' && ch<='9' ||
		   ch=='-' || ch=='.' || ch=='_' || ch=='~' || ch=='+' || ch=='/') { return false }
	}
	if header[at]=='=' { return false }
	return true
}

transfer :: proc(t:^Transfer,frame:Frame,input:m.ProjectionInput,secret:l.Fd) -> string {
	buf:[m.RequestBodyLimit]byte
	request,status:=m.build_chat_request(input,buf[:])
	if status!=.Ok { return "InvalidProjection" }
	t.request=request
	defer t.request=nil
	auth:[1050]byte
	defer for &b in auth { b=0 }
	ok:=credential(secret,auth[:])
	l.close(secret)
	if !ok { return "CredentialUnavailable" }
	packet:Frame
	for readable(t.control,now_ms()+1) {
		n,fd:=receive(t.control,packet[:])
		if fd>=0 { l.close(fd); return "InvalidHandoff" }
		if n==0 || n==1 && packet[0]=='C' { return "Cancelled" }
		if n!=len(frame) || packet!=frame { return "InvalidHandoff" }
	}
	now:=now_ms()
	if now<0 || now>=t.setup_end { return "Deadline" }
	if !send(t.control,transmute([]byte)string("R")) { return "Cancelled" }
	for readable(t.control,t.setup_end) {
		n,fd:=receive(t.control,packet[:])
		if fd<0 && n==len(frame) && packet==frame { continue }
		if fd<0 && (n==0 || n==1 && packet[0]=='C') { return "Cancelled" }
		if fd<0 || n!=7 || packet[0]!='S' { return "InvalidHandoff" }
		t.socket=fd
		defer if !t.yielded { l.close(fd) }
		peer:l.Sock_Addr_Any
		kind:i32
		_,ke:=l.getsockopt(fd,1,.TYPE,&kind)
		// The trusted connector sends the independently selected IPv4 address and port with the descriptor.
		if !Fixture || ke!=.NONE || kind!=1 || l.getpeername(fd,&peer)!=.NONE || peer.sa_family!=.INET ||
		   peer.ipv4.sin_port!=443 || packet[5]!=1 || packet[6]!=187 || string(peer.ipv4.sin_addr[:])!=string(packet[1:5]) { return "SocketDenied" }
		pin:=fmt.ctprintf("api.openai.com:443:%d.%d.%d.%d",packet[1],packet[2],packet[3],packet[4])
		outcome:=perform(t,cast(cstring)&auth[0],pin)
		return t.failure if t.failure!="" else outcome
	}
	return "Deadline"
}

run :: proc() -> int {
	if Fixture && len(os.args)==2 && os.args[1]=="--test-callbacks" {
		return 0 if callback_controls() else 1
	}
	if len(os.args)==2 && os.args[1]=="--identity" {
		v:=curl.version_info(.ELEVENTH)
		if v==nil || v.age<.ELEVENTH { return 1 }
		for i:=0; v.feature_names[i]!=nil; i+=1 { fmt.print(v.feature_names[i]," ") }
		fmt.println()
		fmt.println("libcurl",v.version,"TLS",v.ssl_version,"features",v.features,"CAfile",CAFile,"CApath",CADir)
		return 0
	}
	if !Fixture || len(os.args)!=1 || l.getuid()!=0 { return 1 }
	return launch()
}
main :: proc() { os.exit(run()) }
