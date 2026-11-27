package main

import "core:encoding/endian"
import "core:testing"
import m "../../src/model"
import l "core:sys/linux"

// Exercise the non-fixture success wire locally, without trusting a synthetic CA.
@(test)
normal_selection_wire :: proc(t:^testing.T) {
	testing.expect(t,Production && ExternalPolicy && !Fixture && !TestRoots)
	id :: "0123456789abcdef0123456789abcdef"
	response :: `{"object":"chat.completion","model":"gpt-5.4-mini-2026-03-17","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"{\"schema_version\":1,\"request_id\":\"0123456789abcdef0123456789abcdef\",\"action\":\"create_marker\",\"expected_effect\":\"marker_contains_payload\",\"payload_b64\":\"YWJj\"}"}}]}`
	frame:Frame
	copy(frame[:4],"WBT1")
	copy(frame[4:36],id)
	endian.put_u32(frame[36:40],.Little,1)
	endian.put_u32(frame[40:44],.Little,2)
	channels:[2][2]l.Fd
	for &pair in channels {
		testing.expect(t,l.socketpair(.LOCAL,.SEQPACKET,l.Protocol(0),&pair)==.NONE)
	}
	defer for pair in channels { l.close(pair[0]); l.close(pair[1]) }

	input:[512]byte
	endian.put_u32(input[:4],.Little,200)
	endian.put_u32(input[4:8],.Little,790)
	endian.put_u32(input[8:12],.Little,80)
	endian.put_u32(input[12:16],.Little,len(response))
	copy(input[16:19],"Ok\x00")
	copy(input[19:],response)
	testing.expect(t,send(channels[0][0],input[:19+len(response)]))
	testing.expect(t,run_front(channels[0][1],channels[1][0],frame,now_ms()+1000))

	got:[128]byte
	n,fd:=receive(channels[1][1],got[:])
	expected:[59]byte
	copy(expected[:19],input[:19])
	copy(expected[19:51],id)
	endian.put_u32(expected[51:55],.Little,2)
	endian.put_u32(expected[55:59],.Little,3)
	testing.expect(t,fd<0 && n==len(expected) && string(got[:len(expected)])==string(expected[:]))
	testing.expect(t,normal_reply(expected[:],frame))
	// A fixture-sized success, invalid echo or oversized counter cannot cross the normal issuer boundary.
	testing.expect(t,!normal_reply(got[:len(expected)+32],frame))
	for off in ([?]int{19,51,55,7}) {
		got[off] ~= 1
		testing.expect(t,!normal_reply(got[:len(expected)],frame))
		got[off] ~= 1
	}
	copy(got[16:],"TlsFailure")
	testing.expect(t,normal_reply(got[:26],frame))
	testing.expect(t,!normal_reply(got[:27],frame))

	input_tuple:=input_for(frame)
	selected,valid:=m.decode_provider_reply(expected[:],input_tuple)
	counts:=m.TransferCounts{200,790,80,len(response)}
	testing.expect(t,valid && selected.counts==counts && selected.outcome==m.Validated_Candidate{2,input_tuple.id,3})
	failure,known:=m.decode_provider_reply(got[:26],input_tuple)
	testing.expect(t,known && failure.outcome==m.ProviderFailure.TlsFailure && failure.counts==counts)
	early:=transmute([]byte)string("CredentialUnavailable")
	preflight,recognized:=m.decode_provider_reply(early,input_tuple)
	testing.expect(t,recognized && preflight.outcome==m.ProviderFailure.CredentialUnavailable && preflight.counts==nil)
	testing.expect(t,!normal_reply(early,frame))
	zero_counts:[16+len("TlsFailure")]byte
	copy(zero_counts[16:],"TlsFailure")
	observed,zero_ok:=m.decode_provider_reply(zero_counts[:],input_tuple)
	testing.expect(t,zero_ok && observed.counts==m.TransferCounts{} && observed.outcome==m.ProviderFailure.TlsFailure)
	for text in ([?]string{"TlsFailure","Ok","Deadline\x00","Spent!"}) {
		_,accepted:=m.decode_provider_reply(transmute([]byte)text,input_tuple)
		testing.expect(t,!accepted)
	}
	for text in ([?]string{"Candidate.PayloadMismatch","Envelope.Refused"}) {
		reason_len:=copy(got[16:],text)
		reply,accepted:=m.decode_provider_reply(got[:16+reason_len],input_tuple)
		testing.expect(t,accepted && reply.counts==counts)
		if text=="Envelope.Refused" { testing.expect(t,reply.outcome==m.ProfileStatus.Refused) }
		else { testing.expect(t,reply.outcome==m.Candidate_Rejection.PayloadMismatch) }
	}
}
