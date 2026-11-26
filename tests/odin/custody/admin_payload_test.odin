package custody_test

import "core:testing"
import "../../../src/custody"
import "../../../src/domain/events"

#assert(events.AuthorizationId != events.CommandId)
// Specification vectors reproduced before codec implementation.
GenesisHistory :: "010101010101010101010101010101010100000000000000444444444444444444444444444444440600726576696577e903000000000000"
GenesisHead :: "4108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18"
EpochWithoutPending :: "010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f020000000000000000000000000000009fe9418f55e10e99815d6efe322509d4d891276b007b130eb66225472a573802666666666666666666666666666666660600726f746174650000000000000000000000000000000000000000000000000000000000000000e903000000000000"
EpochWithPending :: "010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f02000000000000000000000000000000789be34508f45f8144db0001415d4653351e6117b10771660d7e5fa01974772c666666666666666666666666666666660600726f746174659f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4e903000000000000"
RejectionPayload :: "0101010101010101010101010101010101000000000000000f0000000000002de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af01e903000000000000e9030000000000002a00000000000000"
DenialDigest :: "2de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af"

reason_value :: proc(text: string) -> custody.Reason {
	result := custody.Reason{length = len(text)}
	copy(result.bytes[:], text)
	return result
}

genesis_value :: proc() -> custody.Genesis {
	value := custody.Genesis{epoch = 1, reason = reason_value("review"), operator_uid = 1001}
	for &byte in value.store { byte = 1 }
	for &byte in value.authorization { byte = 0x44 }
	return value
}

epoch_value :: proc() -> custody.EpochChange {
	pledge := golden_pledge(golden_bytes())
	value := custody.EpochChange{old = {store = pledge.store, epoch = 1, sequence = 1, head = pledge.head}, reason = reason_value("rotate"), operator_uid = 1001}
	for &byte in value.authorization { byte = 0x66 }
	return value
}

@(test)
genesis_payload_and_head_match_specification :: proc(t: ^testing.T) {
	expected := literal_bytes(GenesisHistory)
	defer delete(expected)
	expected_head := literal_bytes(GenesisHead)
	defer delete(expected_head)
	value := genesis_value()
	encoded, err := custody.encode_genesis(value, value.store)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(encoded.data[:encoded.length]), string(expected))
	decoded, decode_error := custody.decode_genesis(expected, value.store)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	head, head_error := custody.genesis_head(value, value.store)
	testing.expect_value(t, head_error, .None)
	testing.expect_value(t, string(head[:]), string(expected_head))
	value.operator_uid = 0
	root_head, root_error := custody.genesis_head(value, value.store)
	testing.expect_value(t, root_error, .None)
	testing.expect_value(t, root_head, head)
}

@(test)
genesis_rejects_identity_and_reason_errors :: proc(t: ^testing.T) {
	value := genesis_value()
	bad := value
	bad.epoch = 2
	_, err := custody.encode_genesis(bad, value.store)
	testing.expect_value(t, err, .InvalidIdentity)
	bad = value
	bad.authorization = {}
	_, err = custody.encode_genesis(bad, value.store)
	testing.expect_value(t, err, .InvalidIdentity)
	reasons := [3]string{"", "a\x00b", "\xff"}
	for reason in reasons {
		bad = value
		bad.reason = reason_value(reason)
		_, err = custody.encode_genesis(bad, value.store)
		testing.expect_value(t, err, .Malformed)
	}
	value.reason.length = 1024
	for &byte in value.reason.bytes { byte = 'a' }
	encoded, encode_error := custody.encode_genesis(value, value.store)
	testing.expect_value(t, encode_error, .None)
	testing.expect_value(t, encoded.length, 1074)
	decoded, decode_error := custody.decode_genesis(encoded.data[:encoded.length], value.store)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	value.reason.length = 1025
	_, err = custody.encode_genesis(value, value.store)
	testing.expect_value(t, err, .Malformed)
	base, _ := custody.encode_genesis(genesis_value(), value.store)
	_, err = custody.decode_genesis(base.data[:base.length-1], value.store)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.decode_genesis(base.data[:base.length+1], value.store)
	testing.expect_value(t, err, .Malformed)
	base.data[42] = 0xff
	_, err = custody.decode_genesis(base.data[:base.length], value.store)
	testing.expect_value(t, err, .Malformed)
	base.data[42] = 0
	_, err = custody.decode_genesis(base.data[:base.length], value.store)
	testing.expect_value(t, err, .Malformed)
	base, _ = custody.encode_genesis(genesis_value(), value.store)
	base.data[16] = 2
	invalid, identity_error := custody.decode_genesis(base.data[:base.length], value.store)
	testing.expect_value(t, identity_error, .InvalidIdentity)
	testing.expect_value(t, invalid, custody.Genesis{})
}

@(test)
epoch_payloads_bind_pending_and_exclude_uid :: proc(t: ^testing.T) {
	vectors := [2]string{EpochWithoutPending, EpochWithPending}
	pending := literal_bytes(PendingFrame)
	defer delete(pending)
	for vector, index in vectors {
		expected := literal_bytes(vector)
		defer delete(expected)
		value := epoch_value()
		if index == 1 { copy(value.unresolved_pending_record_hash[:], pending[219:]) }
		encoded, err := custody.encode_epoch(value, value.old.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded.data[:encoded.length]), string(expected))
		decoded, decode_error := custody.decode_epoch(expected, value.old.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		value.operator_uid = 0
		root_encoded, root_error := custody.encode_epoch(value, value.old.store, 1)
		testing.expect_value(t, root_error, .None)
		testing.expect_value(t, string(root_encoded.data[80:112]), string(encoded.data[80:112]))
	}
}

@(test)
epoch_rejects_advancement_binding_and_reason_errors :: proc(t: ^testing.T) {
	value := epoch_value()
	base, _ := custody.encode_epoch(value, value.old.store, 1)
	epochs := [2]u8{1, 3}
	for epoch in epochs {
		changed := base
		changed.data[64] = epoch
		_, err := custody.decode_epoch(changed.data[:changed.length], value.old.store, 1)
		testing.expect_value(t, err, .Malformed)
	}
	changed := base
	changed.data[72] = 1
	_, err := custody.decode_epoch(changed.data[:changed.length], value.old.store, 1)
	testing.expect_value(t, err, .Malformed)
	offsets := [2]int{80, base.length-40}
	for offset in offsets {
		changed = base
		changed.data[offset] ~= 1
		_, err = custody.decode_epoch(changed.data[:changed.length], value.old.store, 1)
		testing.expect_value(t, err, .InvalidChecksum)
	}
	_, err = custody.decode_epoch(base.data[:base.length-1], value.old.store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.decode_epoch(base.data[:base.length+1], value.old.store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.decode_epoch(base.data[:base.length], value.old.store, 2)
	testing.expect_value(t, err, .InvalidIdentity)
	value.old.epoch = max(events.Epoch)
	_, err = custody.encode_epoch(value, value.old.store, value.old.epoch)
	testing.expect_value(t, err, .Malformed)
	value = epoch_value()
	value.reason.length = 0
	_, err = custody.encode_epoch(value, value.old.store, 1)
	testing.expect_value(t, err, .Malformed)
	value.reason.length = 1024
	for &byte in value.reason.bytes { byte = 'a' }
	encoded, encode_error := custody.encode_epoch(value, value.old.store, 1)
	testing.expect_value(t, encode_error, .None)
	testing.expect_value(t, encoded.length, 1194)
	decoded, decode_error := custody.decode_epoch(encoded.data[:encoded.length], value.old.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	value.reason.length = 1025
	_, err = custody.encode_epoch(value, value.old.store, 1)
	testing.expect_value(t, err, .Malformed)
}

@(test)
rejection_payload_and_digest_match_specification :: proc(t: ^testing.T) {
	expected := literal_bytes(RejectionPayload)
	defer delete(expected)
	digest_bytes := literal_bytes(DenialDigest)
	defer delete(digest_bytes)
	store := genesis_value().store
	digest, err := custody.denial_digest(nil, 0)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(digest[:]), string(digest_bytes))
	value := custody.Rejection{store = store, epoch = 1, fault_code = 15, request_digest = digest, peer_observed = 1, uid = 1001, gid = 1001, pid = 42}
	encoded, encode_error := custody.encode_rejection(value, store, 1)
	testing.expect_value(t, encode_error, .None)
	testing.expect_value(t, string(encoded[:]), string(expected))
	decoded, decode_error := custody.decode_rejection(expected, store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	value.epoch = 0
	value.uid, value.gid, value.pid = 0, 0, 0
	encoded, encode_error = custody.encode_rejection(value, store, 0)
	testing.expect_value(t, encode_error, .None)
	decoded, decode_error = custody.decode_rejection(encoded[:], store, 0)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
}

@(test)
rejection_enforces_flags_capture_and_peer_rules :: proc(t: ^testing.T) {
	expected := literal_bytes(RejectionPayload)
	defer delete(expected)
	store := genesis_value().store
	value, _ := custody.decode_rejection(expected, store, 1)
	base, _ := custody.encode_rejection(value, store, 1)
	faults := [2]u8{0, 20}
	for fault in faults {
		changed := base
		changed[24] = fault
		_, err := custody.decode_rejection(changed[:], store, 1)
		testing.expect_value(t, err, .Malformed)
	}
	offsets := [2]int{30, 63}
	for offset in offsets {
		changed := base
		changed[offset] = 2
		_, err := custody.decode_rejection(changed[:], store, 1)
		testing.expect_value(t, err, .Malformed)
	}
	value.peer_observed = 0
	_, err := custody.encode_rejection(value, store, 1)
	testing.expect_value(t, err, .Malformed)
	value.uid, value.gid, value.pid = 0, 0, 0
	_, err = custody.encode_rejection(value, store, 1)
	testing.expect_value(t, err, .None)
	value.captured_length = 65547
	encoded, encode_error := custody.encode_rejection(value, store, 1)
	testing.expect_value(t, encode_error, .None)
	_, err = custody.decode_rejection(encoded[:], store, 1)
	testing.expect_value(t, err, .None)
	encoded[26] += 1
	_, err = custody.decode_rejection(encoded[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	value.captured_length = 65548
	_, err = custody.encode_rejection(value, store, 1)
	testing.expect_value(t, err, .Malformed)
	prefix: [65548]u8
	original_digest, _ := custody.denial_digest(prefix[:1], 0)
	prefix[0] = 1
	changed_digest, _ := custody.denial_digest(prefix[:1], 0)
	testing.expect(t, changed_digest != original_digest)
	complete_digest, _ := custody.denial_digest(prefix[:1], 1)
	testing.expect(t, complete_digest != changed_digest)
	_, err = custody.denial_digest(prefix[:65547], 1)
	testing.expect_value(t, err, .None)
	_, err = custody.denial_digest(prefix[:], 1)
	testing.expect_value(t, err, .Malformed)
	_, err = custody.denial_digest(nil, 2)
	testing.expect_value(t, err, .Malformed)
	value.store = {}
	_, err = custody.encode_rejection(value, store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	_, err = custody.decode_rejection(base[:87], store, 1)
	testing.expect_value(t, err, .Malformed)
	excess: [89]u8
	copy(excess[:], base[:])
	_, err = custody.decode_rejection(excess[:], store, 1)
	testing.expect_value(t, err, .Malformed)
}
