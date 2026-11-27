package audit

import e "../domain/events"
import "core:encoding/endian"

// Profile IDs describe the executable profile, independent of the endpoint or
// certificate it encountered. Both use the ADR-0010 pinned provider snapshot.
FailureProfile :: enum u8 {FixtureConnectorV1=1, NormalConnectorV1=2}
FailureClass :: enum u8 {Bare=1, Transport=2, Envelope=3, Candidate=4}
FailureCounts :: struct {http_status, uploaded, headers, received: u32}
FailureDetails :: struct {profile: FailureProfile, class: FailureClass, code: u8, counts: Maybe(FailureCounts)}
ProviderFailureObserved :: struct {
	reference: e.EventRef,
	recorded_time: u64,
	previous_head: [32]u8,
	issuance: e.EventRef,
	id: [16]u8,
	failure: FailureDetails,
}
ProviderFailureBytes :: [156]u8

// The one-based position within each class is its stable wire code. Never
// reorder these tables. A bare and counted Deadline are distinct evidence.
@(private)
BareReasons := [?]string{"CredentialUnavailable","Deadline","Cancelled","InvalidHandoff","Spent"}
@(private)
TransportReasons := [?]string{"ProfileUnavailable","InvalidProjection","CredentialUnavailable","InvalidHandoff",
		"Cancelled","Deadline","DestinationDenied","ResolutionUnavailable","ConnectFailure","SocketDenied",
		"TransportFailure","RequestLimit","RewindDenied","HeaderLimit","Framing","BodyLimit","TlsFailure","RateLimited","HttpFailure"}
@(private)
EnvelopeReasons := [?]string{"InvalidProjection","RequestTooLarge","BodyTooLarge","InvalidEnvelope","WrongModel",
		"Refused","Truncated","ToolOutput","UnexpectedFinish","CandidateTooLarge"}
@(private)
CandidateReasons := [?]string{"CandidateTooLarge","InvalidUtf8","InvalidJson","TrailingContent","MissingKey","UnknownKey",
		"DuplicateKey","WrongFieldType","UnsupportedSchemaVersion","WrongAction","WrongExpectedEffect","RequestIdMismatch",
		"NonCanonicalBase64","DecodedPayloadTooLarge","PayloadMismatch"}

@(private)
failure_names :: proc(class: FailureClass) -> []string {
	switch class {
	case .Bare: return BareReasons[:]
	case .Transport: return TransportReasons[:]
	case .Envelope: return EnvelopeReasons[:]
	case .Candidate: return CandidateReasons[:]
	}
	return nil
}

failure_code :: proc(class: FailureClass,name:string) -> (u8,bool) {
	for known,i in failure_names(class) {
		if known==name { return u8(i+1),true }
	}
	return 0,false
}

@(private)
check_failure :: proc(v:ProviderFailureObserved,store:e.StoreId,epoch:e.Epoch) -> Error {
	if v.id==([16]u8{}) { return .InvalidIdentity }
	if err:=validate_marker_predecessor(v.reference,v.issuance,store,epoch); err!=.None { return err }
	d:=v.failure
	if d.profile!=.NormalConnectorV1 && d.profile!=.FixtureConnectorV1 { return .Unsupported }
	if d.class<.Bare || d.class>.Candidate || d.code==0 || int(d.code)>len(failure_names(d.class)) { return .Unsupported }
	c,present:=d.counts.(FailureCounts)
	if present!=(d.class!=.Bare) || (c.http_status!=0 && (c.http_status<100 || c.http_status>599)) ||
	   c.uploaded>16384 || c.headers>16384 || c.received>65536 { return .Malformed }
	return .None
}

encode_provider_failure :: proc(v:ProviderFailureObserved,store:e.StoreId,epoch:e.Epoch) -> (ProviderFailureBytes,Error) {
	if err:=check_failure(v,store,epoch); err!=.None { return {},err }
	v:=v
	b:ProviderFailureBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},20,9,2)
	write_ref(b[56:88],v.issuance)
	copy(b[88:104],v.id[:])
	b[104],b[105],b[106]=u8(v.failure.profile),u8(v.failure.class),v.failure.code
	if c,present:=v.failure.counts.(FailureCounts); present {
		b[107]=1
		endian.put_u32(b[108:112],.Little,c.http_status)
		endian.put_u32(b[112:116],.Little,c.uploaded)
		endian.put_u32(b[116:120],.Little,c.headers)
		endian.put_u32(b[120:124],.Little,c.received)
	}
	return b,.None
}

decode_provider_failure :: proc(b:[]u8,store:e.StoreId,epoch:e.Epoch) -> (ProviderFailureObserved,Error) {
	env,err:=read_envelope(b,20,9,68,2)
	if err!=.None { return {},err }
	v:=ProviderFailureObserved{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                           issuance=read_ref(b[56:88]),failure={profile=FailureProfile(b[104]),class=FailureClass(b[105]),code=b[106]}}
	copy(v.id[:],b[88:104])
	switch b[107] {
	case 0:
		for byte in b[108:124] { if byte!=0 { return {},.Malformed } }
	case 1:
		c:FailureCounts
		c.http_status,_=endian.get_u32(b[108:112],.Little)
		c.uploaded,_=endian.get_u32(b[112:116],.Little)
		c.headers,_=endian.get_u32(b[116:120],.Little)
		c.received,_=endian.get_u32(b[120:124],.Little)
		v.failure.counts=c
	case: return {},.Malformed
	}
	if issue:=check_failure(v,store,epoch); issue!=.None { return {},issue }
	return v,.None
}
