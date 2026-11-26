package model_test

import "core:encoding/base64"
import "core:fmt"
import "core:strings"
import "core:testing"
import model "../../../src/model"

ID :: "0123456789abcdef0123456789abcdef"
EMPTY :: `{"payload_b64":"","expected_effect":"marker_contains_payload","action":"create_marker",` +
         `"request_id":"` + ID + `","schema_version":1}`

request_id :: proc() -> (id: model.Request_Id) {
	copy(id[:], ID)
	return
}

validate :: proc(input: string, payload: []byte = nil) -> model.Candidate_Result {
	return model.validate_candidate(transmute([]byte)input, request_id(), {17, payload})
}

expect_success :: proc(t: ^testing.T, result: model.Candidate_Result, length: int) {
	value, ok := result.(model.Validated_Candidate)
	if testing.expectf(t, ok, "Expected success, got %v", result) {
		testing.expect_value(t, value, model.Validated_Candidate{17, request_id(), length})
	}
}

expect_rejection :: proc(t: ^testing.T, result: model.Candidate_Result, expected: model.Candidate_Rejection) {
	reason, ok := result.(model.Candidate_Rejection)
	testing.expectf(t, ok && reason == expected, "Expected %v, got %v", expected, result)
}

@(test)
candidate_structure_and_typed_rejections :: proc(t: ^testing.T) {
	expect_success(t, validate(EMPTY), 0)
	expect_success(t, validate(" \r\n\t" + EMPTY), 0)
	expect_rejection(t, validate("[]"), .InvalidJson)
	expect_rejection(t, validate(EMPTY + "{}"), .TrailingContent)
	expect_rejection(t, validate(EMPTY + "\x00"), .TrailingContent)

	Change :: struct {old, new: string, reason: model.Candidate_Rejection}
	changes := [?]Change{
		{`,"action":"create_marker"`, "", .MissingKey},
		{"{", `{"other":"",`, .UnknownKey},
		{"{", `{"action":"create_marker",`, .DuplicateKey},
		{"{", `{"action":"wrong",`, .DuplicateKey},
		{"{", `{"\u0061ction":"create_marker",`, .DuplicateKey},
		{`"schema_version":1`, `"schema_version":true`, .WrongFieldType},
		{`"schema_version":1`, `"schema_version":1.0`, .WrongFieldType},
		{`"create_marker"`, "null", .WrongFieldType},
		{`"marker_contains_payload"`, "[]", .WrongFieldType},
		{`"` + ID + `"`, "1", .WrongFieldType},
		{`"payload_b64":""`, `"payload_b64":{}`, .WrongFieldType},
		{`"schema_version":1`, `"schema_version":2`, .UnsupportedSchemaVersion},
		{"create_marker", "other", .WrongAction},
		{"marker_contains_payload", "other", .WrongExpectedEffect},
		{"012345", "912345", .RequestIdMismatch},
		{"abcdef", "Abcdef", .RequestIdMismatch},
		{"create_marker", `create_marker\uGGGG`, .InvalidJson},
		{"create_marker", `create_marker\'`, .InvalidJson},
		{"{", "{\v", .InvalidJson},
		{"}", ",}", .InvalidJson},
	}
	for change in changes {
		input, replaced := strings.replace_all(EMPTY, change.old, change.new)
		defer if replaced { delete(input) }
		testing.expect(t, replaced)
		expect_rejection(t, validate(input), change.reason)
	}
	escaped, allocated := strings.replace_all(EMPTY, "action", `\u0061ction`)
	defer if allocated { delete(escaped) }
	expect_success(t, validate(escaped), 0)
}

@(test)
candidate_byte_cap_precedes_decoding :: proc(t: ^testing.T) {
	buffer: [8193]byte
	for &c in buffer { c = ' ' }
	copy(buffer[:], EMPTY)
	expect_success(t, validate(string(buffer[:8192])), 0)
	buffer[0] = 0xff
	expect_rejection(t, validate(string(buffer[:8192])), .InvalidUtf8)
	expect_rejection(t, validate(string(buffer[:])), .CandidateTooLarge)
}

@(test)
candidate_requires_canonical_base64 :: proc(t: ^testing.T) {
	for encoded in ([?]string{"YQ", "Y Q=", "!Q==", "YR==", "YWJ="}) {
		field := fmt.aprintf(`"payload_b64":"%s"`, encoded)
		defer delete(field)
		input, allocated := strings.replace_all(EMPTY, `"payload_b64":""`, field)
		defer if allocated { delete(input) }
		expect_rejection(t, validate(input), .NonCanonicalBase64)
	}
}

validate_offered_bytes :: proc(t: ^testing.T, offered, catalog: []byte) -> model.Candidate_Result {
	encoded := base64.encode(offered)
	defer delete(encoded)
	field := fmt.aprintf(`"payload_b64":"%s"`, encoded)
	defer delete(field)
	input, allocated := strings.replace_all(EMPTY, `"payload_b64":""`, field)
	defer if allocated { delete(input) }
	testing.expect(t, len(input) < 8192)
	return validate(input, catalog)
}

@(test)
candidate_matches_complete_catalog_example :: proc(t: ^testing.T) {
	catalog: [4096]byte
	for &c, i in catalog { c = byte(i % 251) }
	offered: [4097]byte
	copy(offered[:], catalog[:])
	expect_success(t, validate_offered_bytes(t, offered[:4096], catalog[:]), 4096)
	expect_success(t, validate_offered_bytes(t, offered[:4096], catalog[:]), 4096)

	offered[4095] += 1
	expect_rejection(t, validate_offered_bytes(t, offered[:4096], catalog[:]), .PayloadMismatch)
	offered[4095] = catalog[4095]
	expect_rejection(t, validate_offered_bytes(t, offered[:], catalog[:]), .DecodedPayloadTooLarge)
}
