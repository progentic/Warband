package main

import "base:runtime"
import curl "vendor:curl"
import c "core:c"
import "core:strings"
import l "core:sys/linux"
import m "../../src/model"

Fixture :: #config(WARBAND_TRANSPORT_FIXTURE,false)
TestRoots :: #config(WARBAND_TEST_ROOTS,Fixture)
when TestRoots {
	CAFile :: "fixture-ca.pem"
	CADir :: "fixture-empty-roots"
} else {
	CAFile :: "/etc/ssl/certs/ca-certificates.crt"
	CADir :: "/etc/ssl/certs"
}
Endpoint :: "https://api.openai.com/v1/chat/completions"
LimitHeaders :: 16384

Transfer :: struct {
	control, socket: l.Fd,
	yielded, authenticated: bool,
	frame: Frame,
	deadline, setup_end: i64,
	request: []byte,
	sent, header_bytes, used: int,
	response: [m.ResponseBodyLimit]byte,
	failure: string,
	status: c.long,
	length_seen, chunked: bool,
}

now_ms :: proc "contextless" () -> i64 {
	t,err:=l.clock_gettime(.BOOTTIME)
	if err!=.NONE { return -1 }
	return i64(t.time_sec)*1000+i64(t.time_nsec/1_000_000)
}

latch :: proc "contextless" (t:^Transfer, reason:string) {
	if t.failure=="" { t.failure=reason }
}

expired :: proc "contextless" (t:^Transfer,now:i64) -> bool {
	return now<0 || now>=t.deadline || (!t.authenticated && now>=t.setup_end)
}
active :: proc "contextless" (t:^Transfer) -> bool {
	if expired(t,now_ms()) { latch(t,"Deadline") }
	f:=[1]l.Poll_Fd{{fd=t.control,events={.IN}}}
	n,e:=l.poll(f[:],0)
	if e!=.NONE { latch(t,"TransportFailure") }
	if n>0 {
		buf:Frame
		got,fd:=receive(t.control,buf[:])
		if fd>=0 { l.close(fd); latch(t,"InvalidHandoff") }
		if got==0 || got==1 && buf[0]=='C' { latch(t,"Cancelled") }
		else if got!=len(buf) || buf!=t.frame { latch(t,"InvalidHandoff") }
	}
	return t.failure==""
}

open_once :: proc "c" (data:rawptr, purpose:curl.socktype, address:^curl.sockaddr) -> curl.socket_t {
	t:=cast(^Transfer)data
	if purpose!=.IPCXN || address.family!=c.int(l.Address_Family.INET) || t.yielded || !active(t) {
		latch(t,"SocketDenied")
		return curl.SOCKET_BAD
	}
	t.yielded=true
	return curl.socket_t(t.socket)
}

connected :: proc "c" (data:rawptr, fd:curl.socket_t, purpose:curl.socktype) -> c.int {
	t:=cast(^Transfer)data
	if purpose==.IPCXN && t.yielded && fd==curl.socket_t(t.socket) { return curl.SOCKOPT_ALREADY_CONNECTED }
	latch(t,"SocketDenied")
	return curl.SOCKOPT_ERROR
}

upload :: proc "c" (dst:[^]byte,size,count:c.size_t,data:rawptr) -> c.size_t {
	t:=cast(^Transfer)data
	if !active(t) { return curl.READFUNC_ABORT }
	if size!=1 || len(t.request)>m.RequestBodyLimit || t.sent>len(t.request) {
		latch(t,"RequestLimit")
		return curl.READFUNC_ABORT
	}
	n:=min(len(t.request)-t.sent,int(min(count,c.size_t(m.RequestBodyLimit))))
	copy(dst[:n],t.request[t.sent:t.sent+n])
	t.sent+=n
	return c.size_t(n)
}

no_rewind :: proc "c" (data:rawptr,_:curl.off_t,_:c.int) -> c.int {
	latch(cast(^Transfer)data,"RewindDenied")
	return curl.SEEKFUNC_FAIL
}

headers :: proc "c" (ptr:[^]byte,size,n:c.size_t,data:rawptr) -> c.size_t {
	context = runtime.default_context()
	t:=cast(^Transfer)data
	if !active(t) { return curl.WRITEFUNC_ERROR }
	if size!=1 || n>c.size_t(LimitHeaders-t.header_bytes) { latch(t,"HeaderLimit"); return curl.WRITEFUNC_ERROR }
	t.header_bytes+=int(n)
	line:=string(ptr[:int(n)])
	if strings.has_prefix(line,"HTTP/1.1 ") {
		t.length_seen,t.chunked=false,false
	} else if line!="\r\n" {
		colon:=strings.index(line,":")
		if colon<=0 || line[0]<=' ' || line[colon-1]<=' ' { latch(t,"Framing"); return curl.WRITEFUNC_ERROR }
		key:=line[:colon]
		value:=strings.trim_space(line[colon+1:])
		if strings.equal_fold(key,"Content-Encoding") && !strings.equal_fold(value,"identity") { latch(t,"Framing") }
		if strings.equal_fold(key,"Content-Length") {
			if t.length_seen || t.chunked || len(value)==0 { latch(t,"Framing") }
			for ch in value { if ch<'0' || ch>'9' { latch(t,"Framing") } }
			t.length_seen=true
		}
		if strings.equal_fold(key,"Transfer-Encoding") {
			if t.length_seen || t.chunked || !strings.equal_fold(value,"chunked") { latch(t,"Framing") }
			t.chunked=true
		}
	}
	return n if t.failure=="" else curl.WRITEFUNC_ERROR
}

body :: proc "c" (ptr:[^]byte,size,n:c.size_t,data:rawptr) -> c.size_t {
	t:=cast(^Transfer)data
	if !active(t) { return curl.WRITEFUNC_ERROR }
	if size!=1 || n>c.size_t(len(t.response)-t.used) { latch(t,"BodyLimit"); return curl.WRITEFUNC_ERROR }
	t.used+=copy(t.response[t.used:],ptr[:int(n)])
	return n
}

before_request :: proc "c" (data:rawptr,_:cstring,_:cstring,_:c.int,_:c.int) -> c.int {
	t:=cast(^Transfer)data
	if !active(t) { return curl.PREREQFUNC_ABORT }
	if t.authenticated { latch(t,"RewindDenied"); return curl.PREREQFUNC_ABORT }
	t.authenticated=true
	return curl.PREREQFUNC_OK
}

progress :: proc "c" (data:rawptr,_:curl.off_t,_:curl.off_t,_:curl.off_t,_:curl.off_t) -> c.int {
	return 0 if active(cast(^Transfer)data) else 1
}

perform :: proc(t:^Transfer, auth:cstring, resolve:cstring) -> string {
	easy:=curl.easy_init()
	if easy==nil { return "TransportFailure" }
	defer curl.easy_cleanup(easy)
	defer _=curl.easy_getinfo(easy,.RESPONSE_CODE,&t.status)
	h:^curl.slist
	defer curl.slist_free_all(h)
	for line in ([3]cstring{"Content-Type: application/json","Expect:",auth}) {
		next:=curl.slist_append(h,line)
		if next==nil { return "TransportFailure" }
		h=next
	}
	// libcurl has copied the bearer header into the last slist node.
	defer for &b in h.next.next.data[:len(string(auth))] { b=0 }
	pin:=curl.slist_append(nil,resolve)
	if pin==nil { return "TransportFailure" }
	defer curl.slist_free_all(pin)
	remaining:=t.deadline-now_ms()
	setup:=min(remaining,t.setup_end-now_ms())
	if setup<=0 || remaining<=0 { return "Deadline" }
	for opt in ([?]struct{k:curl.option,v:c.long}{
		{.POST,1},{.POSTFIELDSIZE,c.long(len(t.request))},{.HTTP_VERSION,curl.HTTP_VERSION_1_1},
		{.FOLLOWLOCATION,0},{.FRESH_CONNECT,1},{.FORBID_REUSE,1},{.HTTPAUTH,0},{.PROXYAUTH,0},
		{.SSL_VERIFYPEER,1},{.SSL_VERIFYHOST,2},{.SSLVERSION,curl.SSLVERSION_TLSv1_2},{.SSL_OPTIONS,0},
		{.HTTP_CONTENT_DECODING,0},{.NOPROGRESS,0},{.NOSIGNAL,1},{.CONNECTTIMEOUT_MS,c.long(setup)},{.TIMEOUT_MS,c.long(remaining)},
	}) { if curl.easy_setopt(easy,opt.k,opt.v)!=.E_OK { return "ProfileUnavailable" } }
	for opt in ([?]struct{k:curl.option,v:cstring}{
		{.URL,Endpoint},{.PROTOCOLS_STR,"https"},{.REDIR_PROTOCOLS_STR,"https"},{.PROXY,""},
		{.CAINFO,CAFile},{.CAPATH,CADir},
	}) { if curl.easy_setopt(easy,opt.k,opt.v)!=.E_OK { return "ProfileUnavailable" } }
	for opt in ([?]struct{k:curl.option,v:rawptr}{
		{.PREREQFUNCTION,rawptr(before_request)},{.PREREQDATA,t},{.RESOLVE,pin},{.HTTPHEADER,h},{.OPENSOCKETFUNCTION,rawptr(open_once)},{.OPENSOCKETDATA,t},
		{.SOCKOPTFUNCTION,rawptr(connected)},{.SOCKOPTDATA,t},{.READFUNCTION,rawptr(upload)},{.READDATA,t},
		{.SEEKFUNCTION,rawptr(no_rewind)},{.SEEKDATA,t},{.HEADERFUNCTION,rawptr(headers)},{.HEADERDATA,t},
		{.WRITEFUNCTION,rawptr(body)},{.WRITEDATA,t},{.XFERINFOFUNCTION,rawptr(progress)},{.XFERINFODATA,t},
	}) { if curl.easy_setopt(easy,opt.k,opt.v)!=.E_OK { return "ProfileUnavailable" } }
	multi:=curl.multi_init()
	if multi==nil { return "TransportFailure" }
	defer curl.multi_cleanup(multi)
	if curl.multi_add_handle(multi,easy)!=.OK { return "TransportFailure" }
	defer curl.multi_remove_handle(multi,easy)
	for active(t) {
		running:c.int
		if curl.multi_perform(multi,&running)!=.OK { return "TransportFailure" }
		if running==0 { break }
		wake:=curl.waitfd{fd=curl.socket_t(t.control),events=curl.WAIT_POLLIN}
		ready:c.int
		if curl.multi_poll(multi,cast([^]curl.waitfd)&wake,1,c.int(clamp(t.deadline-now_ms(),1,100)),&ready)!=.OK { return "TransportFailure" }
	}
	if !active(t) { return t.failure }
	left:c.int
	msg:=curl.multi_info_read(multi,&left)
	if msg==nil || msg.msg!=.DONE || msg.easy_handle!=easy { return "TransportFailure" }
	if curl.easy_getinfo(easy,.RESPONSE_CODE,&t.status)!=.E_OK { return "TransportFailure" }
	#partial switch msg.data.result {
	case .E_PARTIAL_FILE: return "Framing"
	case .E_OPERATION_TIMEDOUT: return "Deadline"
	case .E_PEER_FAILED_VERIFICATION,.E_SSL_CACERT_BADFILE,.E_SSL_CONNECT_ERROR: return "TlsFailure"
	case .E_OK:
	case: return "TransportFailure"
	}
	if t.status==429 { return "RateLimited" }
	if t.status<200 || t.status>=300 { return "HttpFailure" }
	if t.sent!=len(t.request) { return "TransportFailure" }
	return "Ok"
}

// The reviewed catalog cannot produce a 16 KiB request. Exercise the actual
// callbacks at that boundary without giving the transport a raw-body input.
callback_controls :: proc() -> bool {
	pair:[2]l.Fd
	if l.socketpair(.LOCAL,.SEQPACKET,l.Protocol(0),&pair)!=.NONE { return false }
	defer l.close(pair[0]); defer l.close(pair[1])
	src,dst:[m.RequestBodyLimit+1]byte
	t:=Transfer{control=pair[0],setup_end=now_ms()+5000,deadline=now_ms()+30_000,request=src[:m.RequestBodyLimit]}
	if upload(raw_data(dst[:]),1,len(dst),&t)!=m.RequestBodyLimit || t.sent!=m.RequestBodyLimit { return false }
	t.request=src[:]
	if upload(raw_data(dst[:]),1,1,&t)!=curl.READFUNC_ABORT || t.failure!="RequestLimit" { return false }
	t.deadline=now_ms()
	if active(&t) || t.failure!="RequestLimit" { return false }
	t.setup_end,t.deadline=5000,30000
	if expired(&t,4999) || !expired(&t,5000) { return false }
	t.authenticated=true
	return !expired(&t,29999) && expired(&t,30000)
}
