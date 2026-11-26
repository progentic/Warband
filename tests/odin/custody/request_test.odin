package custody_test

import "core:testing"
import "core:encoding/endian"
import "../../../src/custody"

WBCR1_request_hex :: "574243520100018800000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035"
WBCR1_digest :: "70ccdc48356cdd1ac791b24d739c2495ccbeb7e2f88fca7d40ab77b7e3227a5d"
WBCR2_request_hex :: "574243520100028800000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035"
WBCR2_digest :: "674e12cf3cbe91df181ddac8a757e4df86854c6432d02d039a3234c342fa4865"
WBCR3_request_hex :: "57424352010003200000000101010101010101010101010101010101000000000000000807060504030201"
WBCR3_digest :: "1cc3b726d8077c2684e4f577ba7763428250e803edcea0040959d66adecfaf7e"
WBCR4_request_hex :: "5742435201000430000000010101010101010101010101010101010100000000000000444444444444444444444444444444440600726576696577"
WBCR4_digest :: "8beb88df1458295fbd57ec3aefa44c9a102f9c526547dfd258c7322754786f11"
WBCR5_request_hex :: "57424352010005a8000000010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f02000000000000000000000000000000789be34508f45f8144db0001415d4653351e6117b10771660d7e5fa01974772c666666666666666666666666666666660600726f746174659f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4"
WBCR5_digest :: "91e532ac0d0747f0720563b90f25bd8d5f58a98a4782d8024a25f6d0439754fc"

@(test)
requests_match_golden_bytes_and_digests :: proc(t: ^testing.T) {
	pledge := golden_pledge(golden_bytes())
	gen := genesis_value()
	epoch := epoch_value()
	pending := literal_bytes(PendingFrame)
	defer delete(pending)
	copy(epoch.unresolved_pending_record_hash[:], pending[219:])
	values := [?]custody.Request{
		{.Prepare, pledge}, {.Confirm, pledge},
		{.Verify, custody.VerifyRequest{pledge.store, 1, 0x0102030405060708}},
		{.Enroll, custody.EnrollmentRequest{gen.store, gen.epoch, gen.authorization, gen.reason}},
		{.EpochChange, custody.EpochRequest{epoch.old, epoch.authorization, epoch.reason, epoch.unresolved_pending_record_hash}},
	}
	vectors := [?]string{WBCR1_request_hex, WBCR2_request_hex, WBCR3_request_hex, WBCR4_request_hex, WBCR5_request_hex}
	digests := [?]string{WBCR1_digest, WBCR2_digest, WBCR3_digest, WBCR4_digest, WBCR5_digest}
	for value, i in values {
		bytes := literal_bytes(vectors[i])
		defer delete(bytes)
		expected := literal_bytes(digests[i])
		defer delete(expected)
		encoded, err := custody.encode_request(value, pledge.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded.data[:encoded.length]), string(bytes))
		decoded, read_err := custody.decode_request(bytes, pledge.store, 1)
		testing.expect_value(t, read_err, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_err := custody.digest_request(decoded, pledge.store, 1)
		testing.expect_value(t, digest_err, .None)
		testing.expect_value(t, string(digest[:]), string(expected))
	}
}

@(test)
requests_reject_malformed_frames_and_uid_suffixes :: proc(t: ^testing.T) {
	store := genesis_value().store
	admin := [?]string{WBCR4_request_hex, WBCR5_request_hex}
	for text in admin {
		valid := literal_bytes(text)
		defer delete(valid)
		bytes: [custody.MaxRequestSize]u8
		copy(bytes[:], valid)
		write_length := len(valid)+8
		assert(endian.put_u32(bytes[7:11], .Little, u32(write_length-11)))
		assert(endian.put_u64(bytes[len(valid):write_length], .Little, 1001))
		_, err := custody.decode_request(bytes[:write_length], store, 1)
		testing.expect_value(t, err, .Malformed)
	}
	verify := literal_bytes(WBCR3_request_hex)
	defer delete(verify)
	_, err := custody.decode_request(verify[:10], store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.decode_request(verify[:len(verify)-1], store, 1)
	testing.expect_value(t, err, .Malformed)
	excess: [44]u8
	copy(excess[:], verify)
	_, err = custody.decode_request(excess[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.decode_request(verify, store, 2)
	testing.expect_value(t, err, .InvalidIdentity)
	mutations := [?]struct{offset: int, replacement: u8, expected: custody.FormatError}{
		{0, 0, .Malformed}, {4, 2, .Unsupported}, {6, 0, .Unsupported}, {6, 6, .Unsupported}, {7, 0xff, .Malformed},
	}
	for m in mutations {
		saved := verify[m.offset]
		verify[m.offset] = m.replacement
		_, err = custody.decode_request(verify, store, 1)
		testing.expect_value(t, err, m.expected)
		verify[m.offset] = saved
	}
}
