package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

#assert(events.ProposalId != events.TaskId)
// Alternative sequence-2 encoding examples from the published specification.
ProposalEvent0 :: "574245560100020001010101010101010101010101010101010000000000000002000000000000000000000000000000010001004b00000011111111111111111111111111111111222222222222222222222222222222227777777777777777777777777777777701000000000000000100000000000000010000000000000100010000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f"
ProposalDigest0 :: "e836ba89122acce4fceac8e5a4faa54986a2bb1c4c1210f39b5d6a59ccfd05b9"
ProposalFingerprint0 :: "c2406d9f939ac81bf762471f3ef5d5c985f844ee46bce010232b1afbdb57a679"
ProposalHead0 :: "893d1c939240a2180764124ff611de9d4abc3ebb1e84a53e8efb34926c992d55"
ProposalEvent1 :: "574245560100020001010101010101010101010101010101010000000000000002000000000000000000000000000000010001004b00000011111111111111111111111111111111222222222222222222222222222222227777777777777777777777777777777701000000000000000100000000000000010000000000000100010100e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f"
ProposalDigest1 :: "38c5557810938a7dd873981667e83b882c8e9eef5d570a8e3a42d46258e20067"
ProposalFingerprint1 :: "cac5e293f45379b0f7a07cf0f373ae3e957c27c56c2e224fb4645ac1e28c276b"
ProposalHead1 :: "f020586a82fabf8ca1ac5fec5566c76e5ce8600005868d409729c0969464e994"

@(test)
proposal_encoding_and_fingerprint_match_golden :: proc(t: ^testing.T) {
	events_hex := [2]string{ProposalEvent0, ProposalEvent1}
	digests_hex := [2]string{ProposalDigest0, ProposalDigest1}
	fingerprints_hex := [2]string{ProposalFingerprint0, ProposalFingerprint1}
	heads_hex := [2]string{ProposalHead0, ProposalHead1}
	prior_fingerprint: [32]u8
	for event_hex, index in events_hex {
		expected := vector_bytes(event_hex)
		defer delete(expected)
		expected_digest := vector_bytes(digests_hex[index])
		defer delete(expected_digest)
		expected_fingerprint := vector_bytes(fingerprints_hex[index])
		defer delete(expected_fingerprint)
		expected_head := vector_bytes(heads_hex[index])
		defer delete(expected_head)
		value := audit.ProposalRecorded{expected_task_version = 1, policy_version = 1, approval_required = index == 1}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 2
		for &byte in value.task { byte = 0x11 }
		for &byte in value.run { byte = 0x22 }
		for &byte in value.proposal { byte = 0x77 }
		copy(value.previous_head[:], expected[131:])
		encoded, err := audit.encode_proposal_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_proposal_recorded(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_proposal_recorded(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		fingerprint, fingerprint_error := audit.fingerprint_proposal(value, value.reference.store, 1)
		testing.expect_value(t, fingerprint_error, .None)
		testing.expect_value(t, string(fingerprint[:]), string(expected_fingerprint))
		if index == 1 { testing.expect(t, fingerprint != prior_fingerprint) }
		prior_fingerprint = fingerprint
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 2, previous_sequence = 1, previous_head = value.previous_head, digest = digest})
		testing.expect_value(t, string(head[:]), string(expected_head))
		value.proposal[0] = 0x78
		changed, changed_error := audit.fingerprint_proposal(value, value.reference.store, 1)
		testing.expect_value(t, changed_error, .None)
		testing.expect(t, changed != fingerprint)
	}
}

@(test)
proposal_decoding_rejects_wrong_kind_and_payload :: proc(t: ^testing.T) {
	expected := vector_bytes(ProposalEvent0)
	defer delete(expected)
	task_bytes := vector_bytes(GoldenEvent)
	defer delete(task_bytes)
	store: events.StoreId
	for &byte in store { byte = 1 }
	_, err := audit.decode_proposal_recorded(task_bytes, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_task_created(expected, store, 1)
	testing.expect_value(t, err, .Malformed)
	bytes: audit.ProposalRecordedBytes
	copy(bytes[:], expected)
	bytes[52] = 74
	_, err = audit.decode_proposal_recorded(bytes[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	action := 120
	target := 122
	argument_length := 123
	criterion := 127
	recovery := 129
	policy_version := 112
	approval_flag := 130
	unsupported_fields := [7]int{action, target, argument_length, criterion, recovery, policy_version, approval_flag}
	for offset in unsupported_fields {
		copy(bytes[:], expected)
		bytes[offset] = 2
		_, err = audit.decode_proposal_recorded(bytes[:], store, 1)
		testing.expect_value(t, err, .Unsupported)
	}
	identifier_offsets := [3]int{56, 72, 88}
	for offset in identifier_offsets {
		copy(bytes[:], expected)
		for &byte in bytes[offset:offset+16] { byte = 0 }
		invalid, identity_error := audit.decode_proposal_recorded(bytes[:], store, 1)
		testing.expect_value(t, identity_error, .InvalidIdentity)
		testing.expect_value(t, invalid, audit.ProposalRecorded{})
	}
	copy(bytes[:], expected)
	bytes[104] = 0
	_, err = audit.decode_proposal_recorded(bytes[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_proposal_recorded(expected, store, 2)
	testing.expect_value(t, err, .InvalidIdentity)
	_, err = audit.encode_proposal_recorded({}, store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
}
