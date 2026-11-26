package main

import l "core:sys/linux"

ExternalPolicy :: #config(WARBAND_EXTERNAL_CONNECTOR,false)
foreign import policy "system:wb_network_policy"
foreign policy {
	wb_network_profile :: proc() -> i32 ---
	wb_resolve_fixed :: proc(addresses:rawptr,end:i64) -> i32 ---
	wb_connect_fixed :: proc(address:rawptr,end:i64) -> i32 ---
}

DnsAddress :: struct {rr:u8, bytes:[16]u8}
#assert(size_of(DnsAddress)==17)

// IANA ipv4-special-registry and ipv6-special-registry.
// Conservative special-purpose registry exclusions; use only IPv4 for the
// connected 3b descriptor. Check IPv6 as well before selecting any A answer.
eligible_address :: proc(a:DnsAddress) -> bool {
	b:=a.bytes
	if a.rr==28 {
		// RIR allocations from IANA ipv6-unicast-address-assignments (2025-10-10).
		// Unlisted parts of 2000::/3 are reserved. Review this table on profile change.
		prefix:=u16(b[0])<<8 | u16(b[1])
		switch prefix {
		case 0x2001:
			sub:=u16(b[2])<<8 | u16(b[3])
			return sub!=0x0db8 && (sub>=0x0200 && sub<0x1000 || sub>=0x1200 && sub<0x4e00 ||
			                      sub>=0x5000 && sub<0x6000 || sub>=0x8000 && sub<0xc000)
		case 0x2003: return b[2]<64
		case 0x2400..=0x241f,0x2600..=0x260f,0x2610..=0x2611,0x2630..=0x263f,
		     0x2800..=0x280f,0x2a00..=0x2a1f,0x2c00..=0x2c0f: return true
		case 0x2620..=0x2621: return !(prefix==0x2620 && b[2]==0 && b[3]==0x4f && b[4]==0x80 && b[5]==0)
		}
		return false
	}
	if a.rr!=1 { return false }
	switch b[0] {
	case 0,10,127: return false
	case 100: return b[1]<64 || b[1]>=128
	case 169: return b[1]!=254
	case 172: return b[1]<16 || b[1]>=32
	case 192:
		return b[1]!=168 && !(b[1]==0 && (b[2]==0 || b[2]==2)) &&
		       !(b[1]==31 && b[2]==196 || b[1]==52 && b[2]==193 ||
		         b[1]==88 && b[2]==99 || b[1]==175 && b[2]==48)
	case 198: return b[1]!=18 && b[1]!=19 && !(b[1]==51 && b[2]==100)
	case 203: return !(b[1]==0 && b[2]==113)
	}
	return b[0]<224
}

connect_once :: proc(channel:l.Fd,cutoff:i64) -> bool {
	msg:Frame
	if !readable(channel,cutoff) { return false }
	n,unexpected:=receive(channel,msg[:])
	if n!=1 || msg[0]!='R' || unexpected>=0 { return send(channel,transmute([]byte)string("D")) }
	addresses:[32]DnsAddress
	count:=wb_resolve_fixed(&addresses,cutoff)
	if count<0 { return send(channel,transmute([]byte)string("U")) }
	if count==0 || count>len(addresses) { return send(channel,transmute([]byte)string("D")) }
	for a in addresses[:count] {
		if !eligible_address(a) { return send(channel,transmute([]byte)string("D")) }
	}
	first:=addresses[0]
	if first.rr!=1 { return send(channel,transmute([]byte)string("D")) }
	fd:=l.Fd(wb_connect_fixed(&first.bytes,cutoff))
	if fd<0 { return send(channel,transmute([]byte)string("F")) }
	defer l.close(fd)
	peer:l.Sock_Addr_Any
	if l.getpeername(fd,&peer)!=.NONE || peer.sa_family!=.INET || peer.ipv4.sin_port!=443 ||
	   string(peer.ipv4.sin_addr[:])!=string(first.bytes[:4]) || now_ms()>=cutoff {
		return send(channel,transmute([]byte)string("D"))
	}
	packet:=[7]u8{'S',first.bytes[0],first.bytes[1],first.bytes[2],first.bytes[3],1,187}
	control:=[3]u64{20,1<<32|1,u64(fd)} // Linux x64 CMSG_LEN(sizeof(int)), SOL_SOCKET, SCM_RIGHTS
	vec:=[1]l.IO_Vec{{raw_data(packet[:]),len(packet)}}
	h:=l.Msg_Hdr{iov=vec[:],control=(cast(^[24]u8)&control)[:]}
	sent,err:=l.sendmsg(channel,&h,{.NOSIGNAL,.DONTWAIT})
	return err==.NONE && sent==len(packet)
}
