package model_test

import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:testing"
import m "../../../src/model"

@(test)
chat_projection_is_closed_and_deterministic :: proc(t:^testing.T) {
	buf: [m.RequestBodyLimit]byte
	input := m.ProjectionInput{request_id(),1,1}
	// Independent Python JSON serialization of the two complete request objects.
	for golden,i in ([?]string{"e82525efc9ca7cbbeec78ffca42e4bbbd46eb95ba037f8b32f7f8948945d5123",
	                           "1c564761ec41d5562ec25b7e3b85e359eab68a48ee29416f7d7a2d4a3453c5b3"}) {
		input.example=m.Catalog_Id(i+1)
		body,status:=m.build_chat_request(input,buf[:])
		testing.expect_value(t,status,m.ProfileStatus.Ok)
		digest:=m.catalog_digest(string(body))
		text:=hex.encode(digest[:]); defer delete(text)
		testing.expect_value(t,string(text),golden)
		_,short:=m.build_chat_request(input,buf[:len(body)-1])
		testing.expect_value(t,short,m.ProfileStatus.RequestTooLarge)
	}
	for bad in ([?]m.ProjectionInput{{request_id(),2,1},{request_id(),1,3},{id={},revision=1,example=1}}) {
		body,status:=m.build_chat_request(bad,buf[:])
		testing.expect(t,len(body)==0 && status==.InvalidProjection)
	}
	input.id[10]='A'
	_,bad:=m.build_chat_request(input,buf[:])
	testing.expect_value(t,bad,m.ProfileStatus.InvalidProjection)
}

completion :: proc(content:string) -> string {
	quoted,err:=json.marshal(content,{spec=.JSON})
	assert(err==nil)
	defer delete(quoted)
	return strings.concatenate({`{"object":"chat.completion","model":"` + m.ChatModel +
	                           `","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","refusal":null,"content":`,
	                           string(quoted),`}}],"usage":{"canary":[true,null,{"x":2.5}]}}`})
}

@(test)
chat_envelope_and_direct_fixture_share_validator :: proc(t:^testing.T) {
	input:=m.ProjectionInput{request_id(),1,1}
	fresh:=m.ProjectionInput{request_id(),1,2}
	fresh.id[0]='a'
	baseline:[m.RequestBodyLimit]u8
	before,ready:=m.build_chat_request(fresh,baseline[:])
	testing.expect(t,ready==.Ok)
	// Preserve JSON escapes inside the candidate for the candidate reader.
	content,allocated:=strings.replace_all(EMPTY,"action",`\u0061ction`)
	defer if allocated { delete(content) }
	body:=completion(content); defer delete(body)
	dst:[m.MAX_CANDIDATE_BYTES]u8
	extracted,status:=m.extract_chat_candidate(transmute([]u8)body,&dst)
	testing.expect(t,status==.Ok && string(extracted)==content)
	direct:=m.validate_candidate(transmute([]byte)content,input.id,{1,nil})
	result:=m.validate_chat_completion(transmute([]byte)body,input)
	expected:=m.Validated_Candidate{1,input.id,0}
	testing.expect(t,direct==expected && result==expected)
	input.example=2
	testing.expect(t,m.validate_chat_completion(transmute([]byte)body,input)==m.Candidate_Rejection.PayloadMismatch)
	abc,changed:=strings.replace_all(EMPTY,`"payload_b64":""`,`"payload_b64":"YWJj"`)
	defer if changed { delete(abc) }
	reply:=completion(abc); defer delete(reply)
	from_reply:=m.validate_chat_completion(transmute([]byte)reply,input)
	from_fixture:=m.validate_candidate(transmute([]byte)abc,input.id,{2,transmute([]byte)string("abc")})
	abc_selection:=m.Validated_Candidate{2,input.id,3}
	testing.expect(t,from_reply==abc_selection && from_fixture==abc_selection)
	// Metadata and prior reply contents cannot become part of a future projection.
	next:[m.RequestBodyLimit]u8
	built,ok:=m.build_chat_request(fresh,next[:])
	testing.expect(t,ok==.Ok && string(built)==string(before) && !strings.contains(string(built),"canary") && !strings.contains(string(built),ID))
}

@(test)
chat_envelope_rejects_conflicts_and_incomplete_results :: proc(t:^testing.T) {
	initial:=completion("deliberately invalid candidate"); defer delete(initial)
	Change :: struct {old,new:string,reason:m.ProfileStatus}
	for v in ([?]Change{
		{`"object":"chat.completion",`,"",.InvalidEnvelope},
		{`"refusal":null`,`"refusal":true`,.InvalidEnvelope},
		{`"usage":`,`"usage":null,"\u0075sage":`,.InvalidEnvelope},
		{"chat.completion","chat.completion.chunk",.InvalidEnvelope},
		{m.ChatModel,"other",.WrongModel}, {`"index":0`,`"index":1`,.InvalidEnvelope},
		{`"choices":[`,`"choices":[{},`,.InvalidEnvelope},
		{`"index":0`,`"index":0,"delta":{}`,.InvalidEnvelope},
		{`"role":"assistant"`,`"role":"tool"`,.InvalidEnvelope},
		{`"refusal":null`,`"refusal":"denied"`,.Refused},
		{`"refusal":null`,`"tool_calls":[]`,.ToolOutput},
		{`"refusal":null`,`"function_call":{}`,.ToolOutput},
		{`"stop"`,`"length"`,.Truncated}, {`"stop"`,`"content_filter"`,.Refused},
		{`"stop"`,`"tool_calls"`,.ToolOutput}, {`"stop"`,`"other"`,.UnexpectedFinish},
		{`"index":0`,`"index":0,"\u0069ndex":0`,.InvalidEnvelope},
		{`"role":"assistant"`,`"role":"assistant","role":"assistant"`,.InvalidEnvelope},
		{`"usage":`,`"usage":null,"usage":`,.InvalidEnvelope},
		{`"usage":`,`"error":{},"usage":`,.InvalidEnvelope},
		{`"x":2.5`,`"x":2.5,`,.InvalidEnvelope}, {`"x":2.5`,`"x":"\uD800"`,.InvalidEnvelope},
		{`"x":2.5`,`"x":"\u00GG"`,.InvalidEnvelope}, {`"x":2.5`,`"x":"\'"`,.InvalidEnvelope},
		{`"content":"deliberately invalid candidate"`,`"content":[]`,.InvalidEnvelope},
		{`"finish_reason":"stop",`,"",.InvalidEnvelope},
	}) {
		body,replaced:=strings.replace_all(initial,v.old,v.new)
		defer if replaced { delete(body) }
		got:=m.validate_chat_completion(transmute([]byte)body,{request_id(),1,1})
		testing.expectf(t,replaced && got==v.reason,"change %s: expected %v, got %v",v.new,v.reason,got)
	}
	buffer:[m.MAX_CANDIDATE_BYTES]u8
	trailing:=strings.concatenate({initial,"{}"}); defer delete(trailing)
	_,bad:=m.extract_chat_candidate(transmute([]u8)trailing,&buffer)
	testing.expect_value(t,bad,m.ProfileStatus.InvalidEnvelope)
}

@(test)
chat_enforces_response_and_candidate_byte_boundaries :: proc(t:^testing.T) {
	dst:[m.MAX_CANDIDATE_BYTES]u8
	body:=completion(EMPTY); defer delete(body)
	padded:[m.ResponseBodyLimit+1]u8
	for &b in padded { b=' ' }
	copy(padded[:],body)
	bytes,ok:=m.extract_chat_candidate(padded[:m.ResponseBodyLimit],&dst)
	testing.expect(t,ok==.Ok && string(bytes)==EMPTY)
	_,over:=m.extract_chat_candidate(padded[:],&dst)
	testing.expect_value(t,over,m.ProfileStatus.BodyTooLarge)
	padded[0]=0xff
	_,bad:=m.extract_chat_candidate(padded[:m.ResponseBodyLimit],&dst)
	testing.expect_value(t,bad,m.ProfileStatus.InvalidEnvelope)
	for n in ([?]int{8192,8193}) {
		content:=strings.repeat(" ",n-len(EMPTY)); defer delete(content)
		value:=fmt.aprintf("%s%s",EMPTY,content); defer delete(value)
		envelope:=completion(value); defer delete(envelope)
		got:=m.validate_chat_completion(transmute([]byte)envelope,{request_id(),1,1})
		if n==8192 { testing.expect(t,got==(m.Validated_Candidate{1,request_id(),0})) }
		else { testing.expect(t,got==m.ProfileStatus.CandidateTooLarge) }
	}
}
