package custody_test

import "core:testing"
import "core:encoding/hex"
import "../../../src/custody"
import "../../../src/domain/events"

// Literal specification vector, independently reproduced before this codec.
GoldenTuple :: "01010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035"

golden_bytes :: proc() -> custody.PledgeBytes {
	hex_bytes: [len(GoldenTuple)]u8
	copy(hex_bytes[:], GoldenTuple)
	decoded, ok := hex.decode(hex_bytes[:])
	assert(ok)
	defer delete(decoded)
	result: custody.PledgeBytes
	copy(result[:], decoded)
	return result
}

golden_pledge :: proc(bytes: custody.PledgeBytes) -> events.Pledge {
	bytes := bytes
	value := events.Pledge{epoch = 1, sequence = 1}
	for &byte in value.store { byte = 1 }
	copy(value.previous_head[:], bytes[32:64])
	copy(value.head[:], bytes[72:104])
	copy(value.digest[:], bytes[104:])
	return value
}

@(test)
pledge_encoding_and_link_match_golden :: proc(t: ^testing.T) {
	expected := golden_bytes()
	value := golden_pledge(expected)
	testing.expect_value(t, custody.derive_head(value), value.head)
	encoded, err := custody.encode_pledge(value, value.store, 1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, encoded, expected)
	decoded, decode_error := custody.decode_pledge(encoded[:], value.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
}

@(test)
pledge_decoding_rejects_length_and_tampering :: proc(t: ^testing.T) {
	bytes := golden_bytes()
	value := golden_pledge(bytes)
	_, err := custody.decode_pledge(bytes[:135], value.store, 1)
	testing.expect_value(t, err, .InvalidLength)
	excess: [137]u8
	copy(excess[:], bytes[:])
	_, err = custody.decode_pledge(excess[:], value.store, 1)
	testing.expect_value(t, err, .InvalidLength)
	changed := bytes
	changed[0] = 2
	_, err = custody.decode_pledge(changed[:], value.store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	changed = bytes
	changed[64] = 2
	_, err = custody.decode_pledge(changed[:], value.store, 1)
	testing.expect_value(t, err, .InvalidSequence)
	changed = bytes
	changed[104] ~= 1
	_, err = custody.decode_pledge(changed[:], value.store, 1)
	testing.expect_value(t, err, .InvalidLink)
}
