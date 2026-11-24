package model

import "core:encoding/base64"
import "core:encoding/json"
import "core:mem"
import "core:unicode/utf8"

MAX_CANDIDATE_BYTES :: 8192
MAX_PAYLOAD_BYTES :: 4096

Catalog_Id :: distinct u32
Request_Id :: distinct [32]byte

Catalog_Example :: struct {
	id: Catalog_Id,
	payload: []byte,
}

Validated_Candidate :: struct {
	example: Catalog_Id,
	request_id: Request_Id,
	decoded_length: int,
}

Candidate_Rejection :: enum {
	CandidateTooLarge, InvalidUtf8, InvalidJson, TrailingContent,
	MissingKey, UnknownKey, DuplicateKey, WrongFieldType,
	UnsupportedSchemaVersion, WrongAction, WrongExpectedEffect, RequestIdMismatch,
	NonCanonicalBase64, DecodedPayloadTooLarge, PayloadMismatch,
}

Candidate_Result :: union {Validated_Candidate, Candidate_Rejection}

@(private)
Field :: enum {Version, Request, Action, Effect, Payload}

@(private)
field_names :: [Field]string{
	.Version = "schema_version", .Request = "request_id", .Action = "action",
	.Effect = "expected_effect", .Payload = "payload_b64",
}

@(private)
json_whitespace :: proc(s: string) -> bool {
	for c in transmute([]byte)s {
		if c != ' ' && c != '\t' && c != '\r' && c != '\n' { return false }
	}
	return true
}

@(private)
next_token :: proc(reader: ^json.Tokenizer) -> json.Token {
	start := reader.offset
	token, err := json.get_token(reader)
	if err != .None || !json_whitespace(reader.data[start:token.offset]) {
		return {}
	}
	return token
}

@(private)
hex_digit :: proc(c: byte) -> bool {
	return ('0' <= c && c <= '9') || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')
}

// The pinned tokenizer also accepts an escaped apostrophe and letters beyond F
// in Unicode escapes. Check those before passing a string to its unquoter.
@(private)
read_string :: proc(token: json.Token, allocator: mem.Allocator) -> (string, bool) {
	raw := token.text
	if token.kind != .String { return "", false }
	for i := 1; i < len(raw)-1; i += 1 {
		if raw[i] != '\\' { continue }
		i += 1
		switch raw[i] {
		case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
		case 'u':
			if i+4 >= len(raw)-1 { return "", false }
			for j in 1..=4 {
				if !hex_digit(raw[i+j]) { return "", false }
			}
			i += 4
		case: return "", false
		}
	}
	value, err := json.unquote_string(token, .JSON, allocator)
	return value, err == .None
}

@(private)
validate_payload :: proc(encoded: string, expected_id: Request_Id, example: Catalog_Example) -> Candidate_Result {
	// Even an over-limit decoded value fits here once the candidate byte cap holds.
	buffer: [MAX_CANDIDATE_BYTES / 4 * 3]byte
	decoded, err := base64.decode_into_buf(buffer[:], encoded, options = {.Strict})
	if err != nil { return Candidate_Rejection.NonCanonicalBase64 }
	if len(decoded) > MAX_PAYLOAD_BYTES { return Candidate_Rejection.DecodedPayloadTooLarge }
	if string(decoded) != string(example.payload) { return Candidate_Rejection.PayloadMismatch }
	return Validated_Candidate{example.id, expected_id, len(decoded)}
}

validate_candidate :: proc(candidate: []byte, expected_id: Request_Id, example: Catalog_Example) -> Candidate_Result {
	if len(candidate) > MAX_CANDIDATE_BYTES { return Candidate_Rejection.CandidateTooLarge }
	input := string(candidate)
	if !utf8.valid_string(input) { return Candidate_Rejection.InvalidUtf8 }
	reader := json.make_tokenizer(input, .JSON, parse_integers = true)
	if reader.offset != 0 || next_token(&reader).kind != .Open_Brace {
		return Candidate_Rejection.InvalidJson
	}

	// Unquoting at most five keys, one duplicate/unknown key, and four values.
	storage: [MAX_CANDIDATE_BYTES + 256]byte
	arena: mem.Arena
	mem.arena_init(&arena, storage[:])
	allocator := mem.arena_allocator(&arena)
	seen: bit_set[Field]
	values: [Field]json.Token
	key := next_token(&reader)
	if key.kind != .Close_Brace {
		for {
			name, ok := read_string(key, allocator)
			if !ok { return Candidate_Rejection.InvalidJson }
			field: Field
			found := false
			for declared_name, index in field_names {
				if name == declared_name {
					field, found = index, true
					break
				}
			}
			if !found { return Candidate_Rejection.UnknownKey }
			if field in seen { return Candidate_Rejection.DuplicateKey }
			seen += {field}
			if next_token(&reader).kind != .Colon { return Candidate_Rejection.InvalidJson }
			value := next_token(&reader)
			#partial switch value.kind {
			case .Open_Brace, .Open_Bracket: return Candidate_Rejection.WrongFieldType
			case .String, .Integer, .Float, .Null, .False, .True: values[field] = value
			case: return Candidate_Rejection.InvalidJson
			}
			separator := next_token(&reader)
			if separator.kind == .Close_Brace { break }
			if separator.kind != .Comma { return Candidate_Rejection.InvalidJson }
			key = next_token(&reader)
		}
	}
	if !json_whitespace(input[reader.offset:]) { return Candidate_Rejection.TrailingContent }
	if seen != (bit_set[Field]{.Version, .Request, .Action, .Effect, .Payload}) {
		return Candidate_Rejection.MissingKey
	}
	if values[.Version].kind != .Integer { return Candidate_Rejection.WrongFieldType }
	if values[.Version].text != "1" { return Candidate_Rejection.UnsupportedSchemaVersion }

	strings: [Field]string
	for field in ([?]Field{.Request, .Action, .Effect, .Payload}) {
		if values[field].kind != .String { return Candidate_Rejection.WrongFieldType }
		value, ok := read_string(values[field], allocator)
		if !ok { return Candidate_Rejection.InvalidJson }
		strings[field] = value
	}
	if strings[.Action] != "create_marker" { return Candidate_Rejection.WrongAction }
	if strings[.Effect] != "marker_contains_payload" { return Candidate_Rejection.WrongExpectedEffect }
	if len(strings[.Request]) != len(expected_id) { return Candidate_Rejection.RequestIdMismatch }
	for digit, i in expected_id {
		if strings[.Request][i] != digit { return Candidate_Rejection.RequestIdMismatch }
		if !(('0' <= digit && digit <= '9') || ('a' <= digit && digit <= 'f')) {
			return Candidate_Rejection.RequestIdMismatch
		}
	}
	return validate_payload(strings[.Payload], expected_id, example)
}
