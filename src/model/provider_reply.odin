package model

import "core:encoding/endian"
import "core:reflect"
import "core:strings"

ProviderHeaderLimit :: 16*1024

ProviderFailure :: enum {
	ProfileUnavailable, InvalidProjection, CredentialUnavailable, InvalidHandoff, Cancelled, Deadline,
	DestinationDenied, ResolutionUnavailable, ConnectFailure, SocketDenied, TransportFailure,
	RequestLimit, RewindDenied, HeaderLimit, Framing, BodyLimit, TlsFailure, RateLimited, HttpFailure, Spent,
}

TransferCounts :: struct {http_status, uploaded, headers, received: u32}
ProviderReply :: struct {
	outcome: union {Validated_Candidate, ProviderFailure, Candidate_Rejection, ProfileStatus},
	counts: Maybe(TransferCounts),
}

// Decode the launcher's existing wire. Bare dispositions have no observed
// counts. All successful results own their selection, independent of packet.
decode_provider_reply :: proc(packet: []byte, issued: ProjectionInput) -> (ProviderReply, bool) {
	if len(packet)==0 || len(packet)>160 { return {},false }
	if early,known:=reflect.enum_from_name(ProviderFailure,string(packet)); known {
		#partial switch early {
		case .InvalidHandoff,.CredentialUnavailable,.Spent,.Deadline,.Cancelled:
			return {outcome=early},true
		}
		return {},false
	}
	if len(packet)<=16 { return {},false }
	counts:TransferCounts
	counts.http_status,_=endian.get_u32(packet[0:4],.Little)
	counts.uploaded,_=endian.get_u32(packet[4:8],.Little)
	counts.headers,_=endian.get_u32(packet[8:12],.Little)
	counts.received,_=endian.get_u32(packet[12:16],.Little)
	if (counts.http_status!=0 && (counts.http_status<100 || counts.http_status>599)) ||
	   counts.uploaded>RequestBodyLimit || counts.headers>ProviderHeaderLimit || counts.received>ResponseBodyLimit {
		return {},false
	}

	result:=packet[16:]
	if len(result)==43 && string(result[:3])=="Ok\x00" {
		expected_id:=issued.id
		example,ok:=catalog_entry(issued.revision,issued.example)
		id,_:=endian.get_u32(result[35:39],.Little)
		length,_:=endian.get_u32(result[39:43],.Little)
		if !ok || counts.http_status<200 || counts.http_status>=300 || counts.uploaded==0 || counts.received==0 ||
		   string(result[3:35])!=string(expected_id[:]) || id!=u32(issued.example) || length!=u32(len(example.payload)) {
			return {},false
		}
		return {Validated_Candidate{issued.example,issued.id,int(length)},counts},true
	}
	name:=string(result)
	if reason,ok:=reflect.enum_from_name(ProviderFailure,name); ok && reason!=.Spent {
		return {reason,counts},true
	}
	if strings.has_prefix(name,"Candidate.") {
		if reason,ok:=reflect.enum_from_name(Candidate_Rejection,name[len("Candidate."):]); ok {
			return {reason,counts},true
		}
	}
	if strings.has_prefix(name,"Envelope.") {
		if reason,ok:=reflect.enum_from_name(ProfileStatus,name[len("Envelope."):]); ok && reason!=.Ok {
			return {reason,counts},true
		}
	}
	return {},false
}
