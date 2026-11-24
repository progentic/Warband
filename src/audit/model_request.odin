package audit

import e "../domain/events"
import "core:encoding/endian"

RequestIssued :: struct {
	reference: e.EventRef,
	recorded_time: u64,
	previous_head: [32]u8,
	id, boot, session: [16]u8,
	revision, catalog_id: u32,
	payload_digest: [32]u8,
	start_ms, deadline_ms: u64,
}
RequestExpiryReason :: enum u8 {Deadline = 1, Cancelled, SessionLost}
RequestExpired :: struct {
	reference: e.EventRef,
	recorded_time: u64,
	previous_head: [32]u8,
	issuance: e.EventRef,
	id: [16]u8,
	reason: RequestExpiryReason,
}
RequestIssuedBytes :: [192]u8
RequestExpiredBytes :: [137]u8

@(private)
check_issuance :: proc(v: RequestIssued, store: e.StoreId, epoch: e.Epoch) -> Error {
	if e.validate_event_ref(v.reference,store,epoch)!=.None || v.id==([16]u8{}) ||
	   v.boot==([16]u8{}) || v.session==([16]u8{}) { return .InvalidIdentity }
	if v.revision==0 || v.catalog_id==0 || v.start_ms>=v.deadline_ms ||
	   v.deadline_ms>u64(max(i64)) || v.deadline_ms-v.start_ms>30_000 { return .Malformed }
	return .None
}

encode_request_issued :: proc(v: RequestIssued, store: e.StoreId, epoch: e.Epoch) -> (RequestIssuedBytes, Error) {
	if err := check_issuance(v,store,epoch); err!=.None { return {},err }
	v := v
	b: RequestIssuedBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},18,9,2)
	copy(b[56:72],v.id[:])
	copy(b[72:88],v.boot[:])
	copy(b[88:104],v.session[:])
	assert(endian.put_u32(b[104:108],.Little,v.revision))
	assert(endian.put_u32(b[108:112],.Little,v.catalog_id))
	copy(b[112:144],v.payload_digest[:])
	assert(endian.put_u64(b[144:152],.Little,v.start_ms))
	assert(endian.put_u64(b[152:160],.Little,v.deadline_ms))
	return b,.None
}

decode_request_issued :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (RequestIssued, Error) {
	env,err := read_envelope(b,18,9,104,2)
	if err!=.None { return {},err }
	v := RequestIssued{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head}
	copy(v.id[:],b[56:72])
	copy(v.boot[:],b[72:88])
	copy(v.session[:],b[88:104])
	v.revision,_ = endian.get_u32(b[104:108],.Little)
	v.catalog_id,_ = endian.get_u32(b[108:112],.Little)
	copy(v.payload_digest[:],b[112:144])
	v.start_ms,_ = endian.get_u64(b[144:152],.Little)
	v.deadline_ms,_ = endian.get_u64(b[152:160],.Little)
	if issue := check_issuance(v,store,epoch); issue!=.None { return {},issue }
	return v,.None
}

@(private)
check_request_expiry :: proc(v: RequestExpired, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.id==([16]u8{}) { return .InvalidIdentity }
	if v.reason<.Deadline || v.reason>.SessionLost { return .Unsupported }
	return validate_marker_predecessor(v.reference,v.issuance,store,epoch)
}

encode_request_expired :: proc(v: RequestExpired, store: e.StoreId, epoch: e.Epoch) -> (RequestExpiredBytes,Error) {
	if err := check_request_expiry(v,store,epoch); err!=.None { return {},err }
	v := v
	b: RequestExpiredBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},19,9,2)
	write_ref(b[56:88],v.issuance)
	copy(b[88:104],v.id[:])
	b[104] = u8(v.reason)
	return b,.None
}

decode_request_expired :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (RequestExpired,Error) {
	env,err := read_envelope(b,19,9,49,2)
	if err!=.None { return {},err }
	v := RequestExpired{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                    issuance=read_ref(b[56:88]),reason=RequestExpiryReason(b[104])}
	copy(v.id[:],b[88:104])
	if issue := check_request_expiry(v,store,epoch); issue!=.None { return {},issue }
	return v,.None
}
