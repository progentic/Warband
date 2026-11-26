package custody_test

import "core:testing"
import "../../../src/custody"

// Specification frames use published payload examples and independent hashes.
GenesisFrame :: "574243480100033800000001000000000000000000000000000000000000000000000000000000000000000000000000000000b43ebea7f7a4d0af04a3011fe4aa9e4ae11cee203736f482456949387c3e9283010101010101010101010101010101010100000000000000444444444444444444444444444444440600726576696577e903000000000000077b460cb9754a2af35338f7168b8113dce3c68385908489bf4cb708443d76ef"
EpochFrame :: "57424348010004b000000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f4750055402635d2dd3095d7ce7559d268eec7af7ec54ae8489bcba23d91608887f5b01010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f020000000000000000000000000000009fe9418f55e10e99815d6efe322509d4d891276b007b130eb66225472a573802666666666666666666666666666666660600726f746174650000000000000000000000000000000000000000000000000000000000000000e903000000000000e48958fde762a31683202ac1cbbcbeccd8efc38ecaec8a779fecaff7e924d096"
EpochPendingFrame :: "57424348010004b000000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f4750055402635d2dd3095d7ce7559d268eec7af7ec54ae8489bcba23d91608887f5b01010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f02000000000000000000000000000000789be34508f45f8144db0001415d4653351e6117b10771660d7e5fa01974772c666666666666666666666666666666660600726f746174659f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4e9030000000000006437b345cbe19cf8dce32dc01e3fbfc4d565b686907a27a835f9896a59b0210e"
RejectionFrame :: "574243480100055800000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005e5afbc47563ec9417ce8285ab50c75f6e6cf05227447a41d5591d6aca4b258c70101010101010101010101010101010101000000000000000f0000000000002de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af01e903000000000000e9030000000000002a00000000000000ee18da5b6b035d42ec9e9c994a11078e6a51b7a00854c23793c78cc2ca1777d2"
BadPayload0 :: "574243480100033800000001000000000000000000000000000000000000000000000000000000000000000000000000000000b43ebea7f7a4d0af04a3011fe4aa9e4ae11cee203736f482456949387c3e9283010101010101010101010101010101010100000000000000000000000000000000000000000000000600726576696577e903000000000000118ce02fb5f2c8daf6ce5732df88b69bf685ae93e18535552fb9301cfaf1d209"
BadPayload1 :: "57424348010004b000000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f4750055402635d2dd3095d7ce7559d268eec7af7ec54ae8489bcba23d91608887f5b01010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f020000000000000000000000000000009ee9418f55e10e99815d6efe322509d4d891276b007b130eb66225472a573802666666666666666666666666666666660600726f746174650000000000000000000000000000000000000000000000000000000000000000e9030000000000000a5c70f5d4f6ac4d4bc15aec36fba061fa0aadd4195101bd1d55e4be4fe21061"
BadPayload2 :: "574243480100055800000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005e5afbc47563ec9417ce8285ab50c75f6e6cf05227447a41d5591d6aca4b258c70101010101010101010101010101010101000000000000000f0000000000022de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af01e903000000000000e9030000000000002a00000000000000e700a7ee468fac9fd3d26a58667f00a00f3470b4317fadcc9477654c6fa34053"
BadPayload3 :: "574243480100033000000001000000000000000000000000000000000000000000000000000000000000000000000000000000d758e70fa96d2c2ff3a38fcc1242e480be1422329d9e623201050349f0c31c3b010101010101010101010101010101010100000000000000444444444444444444444444444444440600726576696577a3d4b5c2e96cc09d8873ff95e617cf89f98e70dc96da22464e999d5207d42035"

record_examples :: proc() -> [4]custody.CustodyRecord {
	pending := literal_bytes(PendingFrame)
	defer delete(pending)
	committed := literal_bytes(CommittedFrame)
	defer delete(committed)
	previous: [32]u8
	copy(previous[:], committed[219:])
	epoch := epoch_value()
	pending_epoch := epoch
	copy(pending_epoch.unresolved_pending_record_hash[:], pending[219:])
	denial, _ := custody.denial_digest(nil, 0)
	rejection := custody.Rejection{store = epoch.old.store, epoch = 1, fault_code = 15, request_digest = denial, peer_observed = 1, uid = 1001, gid = 1001, pid = 42}
	return {{kind = .Genesis, ordinal = 1, payload = genesis_value()},
			{kind = .Epoch, ordinal = 3, previous_record_hash = previous, payload = epoch},
			{kind = .Epoch, ordinal = 3, previous_record_hash = previous, payload = pending_epoch},
			{kind = .Rejection, ordinal = 3, previous_record_hash = previous, payload = rejection}}
}

@(test)
all_kind_frames_match_golden_and_bounds :: proc(t: ^testing.T) {
	vectors := [4]string{GenesisFrame, EpochFrame, EpochPendingFrame, RejectionFrame}
	records := record_examples()
	store := genesis_value().store
	empty: [custody.MaxFrameSize]u8
	max_payload: custody.EpochEncoding
	testing.expect_value(t, custody.FrameOverhead, 51+32+32)
	testing.expect_value(t, custody.MaxFrameSize, 1309)
	testing.expect_value(t, custody.MaxFrameSize, len(max_payload.data)+custody.FrameOverhead)
	for value, index in records {
		expected := literal_bytes(vectors[index])
		defer delete(expected)
		encoded, err := custody.encode_record(value, store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded.data[:encoded.length]), string(expected))
		testing.expect_value(t, string(encoded.data[encoded.length:]), string(empty[:len(empty)-encoded.length]))
		decoded, decode_error := custody.decode_record(expected, store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, decode_error, .None)
		roundtrip, roundtrip_error := custody.encode_record(decoded, store, 1)
		testing.expect_value(t, roundtrip_error, .None)
		testing.expect_value(t, string(roundtrip.data[:roundtrip.length]), string(expected))
		_, err = custody.decode_record(expected[:len(expected)-33], store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, err, .Truncated)
		_, err = custody.decode_record(encoded.data[:encoded.length+1], store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, err, .Malformed)
		encoded.data[7], encoded.data[8], encoded.data[9], encoded.data[10] = 0, 0, 0, 0
		_, err = custody.decode_record(encoded.data[:11], store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, err, .AttestationHistoryFault)
	}
	genesis := genesis_value()
	genesis.reason.length = 1024
	for &byte in genesis.reason.bytes { byte = 'a' }
	epoch := epoch_value()
	epoch.reason = genesis.reason
	max_records := [2]custody.CustodyRecord{{kind = .Genesis, ordinal = 1, payload = genesis}, {kind = .Epoch, ordinal = 3, previous_record_hash = records[1].previous_record_hash, payload = epoch}}
	lengths := [2]int{1074+115,1194+115}
	for value, index in max_records {
		encoded, err := custody.encode_record(value, store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, encoded.length, lengths[index])
		_, err = custody.decode_record(encoded.data[:encoded.length], store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, err, .None)
		excess: [custody.MaxFrameSize+1]u8
		copy(excess[:], encoded.data[:encoded.length])
		_, err = custody.decode_record(excess[:encoded.length+1], store, 1, value.ordinal, value.previous_record_hash)
		testing.expect_value(t, err, .Malformed)
	}
}

@(test)
all_kind_frames_share_corruption_and_payload_rejection :: proc(t: ^testing.T) {
	records := record_examples()
	store := genesis_value().store
	encoded, _ := custody.encode_record(records[1], store, 1)
	cuts := [2]int{10,82}
	offsets := [2]int{0,51}
	for offset, index in offsets {
		changed := encoded
		changed.data[offset] ~= 1
		_, err := custody.decode_record(changed.data[:cuts[index]], store, 1, 3, records[1].previous_record_hash)
		testing.expect_value(t, err, .AttestationHistoryFault)
	}
	partial, _ := custody.encode_record(records[0], store, 1)
	partial.data[7] = 0
	_, partial_error := custody.decode_record(partial.data[:8], store, 1, 1, {})
	testing.expect_value(t, partial_error, .Truncated)
	_, partial_length_error := custody.decode_record(partial.data[:9], store, 1, 1, {})
	testing.expect_value(t, partial_length_error, .AttestationHistoryFault)
	changed := encoded
	changed.data[changed.length-1] ~= 1
	_, err := custody.decode_record(changed.data[:changed.length], store, 1, 3, records[1].previous_record_hash)
	testing.expect_value(t, err, .AttestationHistoryFault)
	_, err = custody.decode_record(encoded.data[:encoded.length], store, 1, 4, records[1].previous_record_hash)
	testing.expect_value(t, err, .AttestationHistoryFault)
	_, err = custody.decode_record(encoded.data[:encoded.length], store, 1, 3, {})
	testing.expect_value(t, err, .AttestationHistoryFault)
	changed = encoded
	changed.data[4] = 2
	_, err = custody.decode_record(changed.data[:changed.length], store, 1, 3, records[1].previous_record_hash)
	testing.expect_value(t, err, .Unsupported)
	changed = encoded
	changed.data[6] = 6
	_, err = custody.decode_record(changed.data[:changed.length], store, 1, 3, records[1].previous_record_hash)
	testing.expect_value(t, err, .Unsupported)
	wrong := records[0]
	wrong.payload = epoch_value()
	_, err = custody.encode_record(wrong, store, 1)
	testing.expect_value(t, err, .Malformed)
	vectors := [4]string{BadPayload0,BadPayload1,BadPayload2,BadPayload3}
	expected := [4]custody.FormatError{.InvalidIdentity,.InvalidChecksum,.Malformed,.AttestationHistoryFault}
	contexts := [4]custody.CustodyRecord{records[0],records[1],records[3],records[0]}
	for text, index in vectors {
		bytes := literal_bytes(text)
		defer delete(bytes)
		value, payload_error := custody.decode_record(bytes, store, 1, contexts[index].ordinal, contexts[index].previous_record_hash)
		testing.expect_value(t, payload_error, expected[index])
		testing.expect_value(t, value.ordinal, u64(0))
	}
}
