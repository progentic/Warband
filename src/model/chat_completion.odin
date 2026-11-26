package model

import "core:encoding/base64"
import "core:encoding/json"
import "core:mem"
import "core:unicode/utf8"

ChatModel :: "gpt-5.4-mini-2026-03-17"
RequestBodyLimit :: 16*1024
ResponseBodyLimit :: 64*1024
ProjectionInput :: struct {id: Request_Id, revision: u32, example: Catalog_Id}
ProfileStatus :: enum {Ok, InvalidProjection, RequestTooLarge, BodyTooLarge, InvalidEnvelope,
                       WrongModel, Refused, Truncated, ToolOutput, UnexpectedFinish, CandidateTooLarge}

// Every interpolated byte comes from either checked lowercase hex or the standard Base64 alphabet.
@(private)
RequestPrefix :: `{"model":"` + ChatModel + `","n":1,"stream":false,"store":false,` +
	`"response_format":{"type":"json_schema","json_schema":{"name":"marker_candidate","strict":true,"schema":` +
	`{"type":"object","additionalProperties":false,"required":["schema_version","request_id","action","expected_effect","payload_b64"],` +
	`"properties":{"schema_version":{"type":"integer","enum":[1]},"request_id":{"type":"string"},` +
	`"action":{"type":"string","enum":["create_marker"]},"expected_effect":{"type":"string","enum":["marker_contains_payload"]},` +
	`"payload_b64":{"type":"string"}}}}},"messages":[{"role":"developer","content":` +
	`"Return the marker proposal matching the schema. Echo the request ID and the Base64 payload exactly."},` +
	`{"role":"user","content":"request_id=`
@(private)
PayloadLabel :: " payload_b64="
@(private)
RequestSuffix :: `"}]}`

@(private)
projection_example :: proc(input: ProjectionInput) -> (CatalogEntry, bool) {
	nonzero := false
	for ch in input.id {
		if !(ch >= '0' && ch <= '9' || ch >= 'a' && ch <= 'f') { return {},false }
		if ch != '0' { nonzero = true }
	}
	if !nonzero { return {},false }
	return catalog_entry(input.revision,input.example)
}

build_chat_request :: proc(input: ProjectionInput, dst: []u8) -> ([]u8,ProfileStatus) {
	entry,ok := projection_example(input)
	if !ok { return nil,.InvalidProjection }
	payload := transmute([]byte)entry.payload
	length := len(RequestPrefix)+len(input.id)+len(PayloadLabel)+base64.encoded_len(payload)+len(RequestSuffix)
	if length>RequestBodyLimit || len(dst)<length { return nil,.RequestTooLarge }
	id := input.id
	at := copy(dst,RequestPrefix)
	at += copy(dst[at:],id[:])
	at += copy(dst[at:],PayloadLabel)
	encoded,err := base64.encode_into_buf(dst[at:length-len(RequestSuffix)],payload)
	if err!=nil { return nil,.InvalidProjection }
	at += len(encoded)
	copy(dst[at:],RequestSuffix)
	return dst[:length],.Ok
}

// Consume a complete JSON value even when its contents are discarded metadata.
@(private)
skip_value :: proc(reader: ^json.Tokenizer, token: json.Token, depth: int) -> bool {
	#partial switch token.kind {
	case .Null,.True,.False,.Integer,.Float: return true
	case .String: return valid_escapes(token.text,true)
	case .Open_Brace,.Open_Bracket:
		if depth>=64 { return false }
		object := token.kind==.Open_Brace
		end := json.Token_Kind.Close_Brace if object else json.Token_Kind.Close_Bracket
		part := next_token(reader)
		if part.kind==end { return true }
		for {
			if object {
				if part.kind!=.String || !valid_escapes(part.text,true) || next_token(reader).kind!=.Colon { return false }
				part = next_token(reader)
			}
			if !skip_value(reader,part,depth+1) { return false }
			separator := next_token(reader)
			if separator.kind==end { return true }
			if separator.kind!=.Comma { return false }
			part = next_token(reader)
		}
	}
	return false
}

@(private)
Member :: struct {name: string, token: json.Token}

// Retain slices only for selected members. The complete decoded key set at each
// interpreted level detects duplicate metadata keys as well as duplicate bindings.
@(private)
members :: proc(input: string, fields: []Member, allocator: mem.Allocator) -> bool {
	reader := json.make_tokenizer(input,.JSON,parse_integers=true)
	if reader.offset!=0 || next_token(&reader).kind!=.Open_Brace { return false }
	seen: map[string]bool
	defer delete(seen)
	key := next_token(&reader)
	if key.kind!=.Close_Brace {
		for {
			name,ok := read_string(key,allocator,true)
			if !ok { return false }
			_,ptr,duplicate := map_upsert(&seen,name,true)
			if ptr==nil || duplicate || next_token(&reader).kind!=.Colon { return false }
			value := next_token(&reader)
			if !skip_value(&reader,value,1) { return false }
			value.text = input[value.offset:reader.offset]
			for &field in fields {
				if field.name==name { field.token=value; break }
			}
			separator := next_token(&reader)
			if separator.kind==.Close_Brace { break }
			if separator.kind!=.Comma { return false }
			key = next_token(&reader)
		}
	}
	return json_whitespace(input[reader.offset:])
}

@(private)
one_choice :: proc(array: json.Token) -> (string,bool) {
	if array.kind!=.Open_Bracket { return "",false }
	reader := json.make_tokenizer(array.text,.JSON,parse_integers=true)
	_ = next_token(&reader)
	first := next_token(&reader)
	if first.kind!=.Open_Brace || !skip_value(&reader,first,1) { return "",false }
	object := array.text[first.offset:reader.offset]
	return object,next_token(&reader).kind==.Close_Bracket
}

@(private)
has_value :: proc(field: Member) -> bool {
	return field.token.kind!=.Invalid && field.token.kind!=.Null
}

extract_chat_candidate :: proc(body: []byte, dst: ^[MAX_CANDIDATE_BYTES]u8) -> ([]byte,ProfileStatus) {
	if len(body)>ResponseBodyLimit { return nil,.BodyTooLarge }
	if !utf8.valid_string(string(body)) { return nil,.InvalidEnvelope }
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	alloc := mem.dynamic_arena_allocator(&arena)

	root := [?]Member{{name="object"},{name="model"},{name="choices"},{name="error"}}
	if !members(string(body),root[:],alloc) || root[3].token.kind!=.Invalid { return nil,.InvalidEnvelope }
	object,object_ok := read_string(root[0].token,alloc,true)
	model,model_ok := read_string(root[1].token,alloc,true)
	if !object_ok || object!="chat.completion" || !model_ok { return nil,.InvalidEnvelope }
	if model!=ChatModel { return nil,.WrongModel }
	choice,one := one_choice(root[2].token)
	fields := [?]Member{{name="index"},{name="finish_reason"},{name="message"},{name="delta"}}
	if !one || !members(choice,fields[:],alloc) || fields[0].token.kind!=.Integer ||
	   fields[0].token.text!="0" || fields[3].token.kind!=.Invalid { return nil,.InvalidEnvelope }
	finish,finish_ok := read_string(fields[1].token,alloc,true)
	if !finish_ok { return nil,.InvalidEnvelope }
	switch finish {
	case "length": return nil,.Truncated
	case "content_filter": return nil,.Refused
	case "function_call","tool_calls": return nil,.ToolOutput
	case "stop":
	case: return nil,.UnexpectedFinish
	}
	msg := [?]Member{{name="role"},{name="content"},{name="refusal"},{name="tool_calls"},{name="function_call"},{name="audio"}}
	if !members(fields[2].token.text,msg[:],alloc) { return nil,.InvalidEnvelope }
	role,role_ok := read_string(msg[0].token,alloc,true)
	if !role_ok || role!="assistant" || has_value(msg[5]) { return nil,.InvalidEnvelope }
	if has_value(msg[2]) {
		if msg[2].token.kind!=.String { return nil,.InvalidEnvelope }
		return nil,.Refused
	}
	if has_value(msg[3]) || has_value(msg[4]) { return nil,.ToolOutput }
	content,text_ok := read_string(msg[1].token,alloc,true)
	if !text_ok { return nil,.InvalidEnvelope }
	if len(content)>len(dst) { return nil,.CandidateTooLarge }
	copy(dst[:],content)
	return dst[:len(content)],.Ok
}

ChatValidation :: union {Validated_Candidate,Candidate_Rejection,ProfileStatus}
validate_chat_completion :: proc(body: []byte,input: ProjectionInput) -> ChatValidation {
	entry,ok := projection_example(input)
	if !ok { return ProfileStatus.InvalidProjection }
	buffer: [MAX_CANDIDATE_BYTES]byte
	candidate,status := extract_chat_candidate(body,&buffer)
	if status!=.Ok { return status }
	switch v in validate_candidate(candidate,input.id,{entry.id,transmute([]byte)entry.payload}) {
	case Validated_Candidate: return v
	case Candidate_Rejection: return v
	}
	unreachable()
}
