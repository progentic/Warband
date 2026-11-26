package audit_test

import "core:testing"
import "core:encoding/hex"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

#assert(events.TaskId != events.RunId)
// Literal ADR-0005 vectors, reproduced independently before implementation.
GoldenEvent :: "5742455601000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f555555555555555555555555555555554108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18"
GoldenDigest :: "e77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035"
GoldenHead :: "00e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f"
UnknownSchema :: "5742455602000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f555555555555555555555555555555554108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18"
TruncatedEvent :: "5742455601000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f555555555555555555555555555555554108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd"

vector_bytes :: proc(text: string) -> []u8 {
	input := make([]u8, len(text))
	defer delete(input)
	copy(input, text)
	bytes, ok := hex.decode(input)
	assert(ok)
	return bytes
}

@(test)
task_created_encoding_and_digest_match_golden :: proc(t: ^testing.T) {
	expected := vector_bytes(GoldenEvent)
	defer delete(expected)
	digest_bytes := vector_bytes(GoldenDigest)
	defer delete(digest_bytes)
	head_bytes := vector_bytes(GoldenHead)
	defer delete(head_bytes)
	value: audit.TaskCreated
	for &byte in value.reference.store { byte = 1 }
	value.reference.epoch = 1
	value.reference.sequence = 1
	for &byte in value.task { byte = 0x11 }
	for &byte in value.run { byte = 0x22 }
	for &byte in value.command { byte = 0x33 }
	for &byte in value.evidence { byte = 0x55 }
	copy(value.input_digest[:], expected[104:136])
	copy(value.previous_head[:], expected[152:])
	encoded, err := audit.encode_task_created(value, value.reference.store, 1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(encoded[:]), string(expected))
	decoded, decode_error := audit.decode_task_created(expected, value.reference.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	digest, digest_error := audit.digest_task_created(value, value.reference.store, 1)
	testing.expect_value(t, digest_error, .None)
	testing.expect_value(t, string(digest[:]), string(digest_bytes))
	pledge := events.Pledge{store = value.reference.store, epoch = 1, sequence = 1, previous_head = value.previous_head, digest = digest}
	head := custody.derive_head(pledge)
	testing.expect_value(t, string(head[:]), string(head_bytes))
	value.input_digest[0] ~= 1
	changed_digest, changed_error := audit.digest_task_created(value, value.reference.store, 1)
	testing.expect_value(t, changed_error, .None)
	testing.expect(t, changed_digest != digest)
}

@(test)
task_created_decoding_rejects_malformed_and_unsupported :: proc(t: ^testing.T) {
	golden := vector_bytes(GoldenEvent)
	defer delete(golden)
	bytes: audit.TaskCreatedBytes
	copy(bytes[:], golden)
	store: events.StoreId
	for &byte in store { byte = 1 }
	unknown := vector_bytes(UnknownSchema)
	defer delete(unknown)
	truncated := vector_bytes(TruncatedEvent)
	defer delete(truncated)
	_, err := audit.decode_task_created(unknown, store, 1)
	testing.expect_value(t, err, .Unsupported)
	_, err = audit.decode_task_created(truncated, store, 1)
	testing.expect_value(t, err, .Malformed)
	excess: [185]u8
	copy(excess[:], bytes[:])
	_, err = audit.decode_task_created(excess[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	unsupported_offsets := [3]int{6, 48, 50}
	for offset in unsupported_offsets {
		changed := bytes
		changed[offset] = 2
		_, err = audit.decode_task_created(changed[:], store, 1)
		testing.expect_value(t, err, .Unsupported)
	}
	malformed_offsets := [2]int{0, 52}
	for offset in malformed_offsets {
		changed := bytes
		changed[offset] = 0
		_, err = audit.decode_task_created(changed[:], store, 1)
		testing.expect_value(t, err, .Malformed)
	}
	identifier_fields := [7][2]int{{8, 24}, {24, 32}, {32, 40}, {56, 72}, {72, 88}, {88, 104}, {136, 152}}
	for field in identifier_fields {
		changed := bytes
		for &byte in changed[field[0]:field[1]] { byte = 0 }
		invalid, identity_error := audit.decode_task_created(changed[:], store, 1)
		testing.expect_value(t, identity_error, .InvalidIdentity)
		testing.expect_value(t, invalid, audit.TaskCreated{})
	}
	_, err = audit.decode_task_created(bytes[:], store, 2)
	testing.expect_value(t, err, .InvalidIdentity)
	_, err = audit.encode_task_created({}, store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
}
