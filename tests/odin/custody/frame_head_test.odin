package custody_test

import "core:testing"
import "core:encoding/hex"
import "../../../src/custody"

// Published specification literals, independently reproduced before implementation.
PendingFrame :: "574243480100018800000001000000000000000000000000000000000000000000000000000000000000000000000000000000f7616841dd9b538e95b95c894d1dfef777e67269157d7bb3f13a4825bf59b9d201010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f80359f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4"
CommittedFrame :: "574243480100028800000002000000000000009f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4a22cf5c0193270d4f576d3edf0cb9bed68b13b9fd33bc62f07f3d2486774e69301010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f80358ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005"
HeadFile :: "574248440100010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f8ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f47500507119d52184d55b10a24ca2ef1c1eff31f8d2a75490a52676d69671476b08faa"
CorruptFrame :: "574243480100018800000001000000000000000000000000000000000000000000000000000000000000000000000000000000f7616841dd9b538e95b95c894d1dfef777e67269157d7bb3f13a4825bf59b9d201010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f80359f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f5"

literal_bytes :: proc(text: string) -> []u8 {
	input := make([]u8, len(text))
	defer delete(input)
	copy(input, text)
	bytes, ok := hex.decode(input)
	assert(ok)
	return bytes
}

@(test)
frame_and_head_encoding_match_golden :: proc(t: ^testing.T) {
	pledge := golden_pledge(golden_bytes())
	vectors := [2]string{PendingFrame, CommittedFrame}
	previous: [32]u8
	for vector, index in vectors {
		expected := literal_bytes(vector)
		defer delete(expected)
		value := custody.Frame{kind = custody.FrameKind(index+1), ordinal = u64(index+1), previous_record_hash = previous, pledge = pledge}
		encoded, err := custody.encode_frame(value, pledge.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := custody.decode_frame(expected, pledge.store, 1, value.ordinal, previous)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		copy(previous[:], expected[219:])
	}
	expected := literal_bytes(HeadFile)
	defer delete(expected)
	value := custody.HeadFile{checkpoint = {store = pledge.store, epoch = 1, sequence = 1, head = pledge.head}, committed_record_hash = previous}
	encoded, err := custody.encode_head_file(value, pledge.store, 1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(encoded[:]), string(expected))
	decoded, decode_error := custody.decode_head_file(expected, pledge.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
}

@(test)
frame_decoding_distinguishes_truncation_and_corruption :: proc(t: ^testing.T) {
	pledge := golden_pledge(golden_bytes())
	expected := literal_bytes(PendingFrame)
	defer delete(expected)
	bytes: custody.FrameBytes
	copy(bytes[:], expected)
	lengths := [3]int{10, 82, 250}
	for length in lengths {
		_, err := custody.decode_frame(bytes[:length], pledge.store, 1, 1, {})
		testing.expect_value(t, err, .Truncated)
	}
	corrupt := literal_bytes(CorruptFrame)
	defer delete(corrupt)
	rejected, err := custody.decode_frame(corrupt, pledge.store, 1, 1, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
	testing.expect_value(t, rejected, custody.Frame{})
	offsets := [3]int{0, 51, 187}
	for offset in offsets {
		changed := bytes
		changed[offset] ~= 1
		_, err = custody.decode_frame(changed[:], pledge.store, 1, 1, {})
		testing.expect_value(t, err, .AttestationHistoryFault)
	}
	bytes[0] = 0
	_, err = custody.decode_frame(bytes[:10], pledge.store, 1, 1, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
	copy(bytes[:], expected)
	bytes[51] ~= 1
	_, err = custody.decode_frame(bytes[:82], pledge.store, 1, 1, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
	copy(bytes[:], expected)
	_, err = custody.decode_frame(bytes[:], pledge.store, 1, 2, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
	_, err = custody.decode_frame(bytes[:], pledge.store, 2, 1, {})
	testing.expect_value(t, err, .InvalidPledge)
	bytes[4] = 2
	_, err = custody.decode_frame(bytes[:], pledge.store, 1, 1, {})
	testing.expect_value(t, err, .Unsupported)
	copy(bytes[:], expected)
	bytes[6] = 3
	_, err = custody.decode_frame(bytes[:], pledge.store, 1, 1, {})
	testing.expect_value(t, err, .Unsupported)
	excess: [252]u8
	copy(excess[:], expected)
	_, err = custody.decode_frame(excess[:], pledge.store, 1, 1, {})
	testing.expect_value(t, err, .Malformed)
	_, err = custody.encode_frame({kind = .Pending, pledge = pledge}, pledge.store, 1)
	testing.expect_value(t, err, .InvalidOrdinal)
	committed := literal_bytes(CommittedFrame)
	defer delete(committed)
	_, err = custody.decode_frame(committed, pledge.store, 1, 2, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
}

@(test)
head_decoding_checks_shape_checksum_and_scope :: proc(t: ^testing.T) {
	pledge := golden_pledge(golden_bytes())
	expected := literal_bytes(HeadFile)
	defer delete(expected)
	bytes: custody.HeadBytes
	copy(bytes[:], expected)
	_, err := custody.decode_head_file(bytes[:133], pledge.store, 1)
	testing.expect_value(t, err, .Malformed)
	excess: [135]u8
	copy(excess[:], expected)
	_, err = custody.decode_head_file(excess[:], pledge.store, 1)
	testing.expect_value(t, err, .Malformed)
	bytes[4] = 2
	_, err = custody.decode_head_file(bytes[:], pledge.store, 1)
	testing.expect_value(t, err, .Unsupported)
	copy(bytes[:], expected)
	bytes[38] ~= 1
	rejected, checksum_error := custody.decode_head_file(bytes[:], pledge.store, 1)
	testing.expect_value(t, checksum_error, .InvalidChecksum)
	testing.expect_value(t, rejected, custody.HeadFile{})
	value, scope_error := custody.decode_head_file(expected, pledge.store, 2)
	testing.expect_value(t, scope_error, .InvalidIdentity)
	testing.expect_value(t, value, custody.HeadFile{})
	value, _ = custody.decode_head_file(expected, pledge.store, 1)
	value.checkpoint.sequence = 0
	encoded, encode_error := custody.encode_head_file(value, pledge.store, 1)
	testing.expect_value(t, encode_error, .None)
	decoded, decode_error := custody.decode_head_file(encoded[:], pledge.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
}
