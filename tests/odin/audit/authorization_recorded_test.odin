package audit_test

import "core:testing"
import "core:encoding/endian"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

#assert(events.CapabilityId != events.AuthorizationId)
// Three alternative encoding examples, constructed before the codec.
AuthorizationEvent0 :: "574245560100030001010101010101010101010101010101010000000000000003000000000000000706050403020100020001005200000001010101010101010101010101010101010000000000000002000000000000000102030405060708018888888888888888888888888888888808070605040302010199999999999999999999999999999999893d1c939240a2180764124ff611de9d4abc3ebb1e84a53e8efb34926c992d55"
AuthorizationDigest0 :: "c4d447059c1f7f3adfedcd3ff9d9672156b8ecb3e9056b39bfcf8b586dcf63a8"
AuthorizationHead0 :: "14aebf797b39d30c13cee72bebecb1d5e6be6426550eee74b5165f30966bb095"
AuthorizationEvent1 :: "574245560100030001010101010101010101010101010101010000000000000003000000000000000706050403020100020001005200000001010101010101010101010101010101010000000000000002000000000000000102030405060708020000000000000000000000000000000000000000000000000099999999999999999999999999999999893d1c939240a2180764124ff611de9d4abc3ebb1e84a53e8efb34926c992d55"
AuthorizationDigest1 :: "b71d38800f5abed24c837e368dc9d09daa74093e6674e17d80c55ee5bb89224c"
AuthorizationHead1 :: "f87e218158421bdaa838b214a5c78e2e17a5ca41cdcab1f83daf17fa03cea978"
AuthorizationEvent2 :: "574245560100030001010101010101010101010101010101010000000000000003000000000000000706050403020100020001005200000001010101010101010101010101010101010000000000000002000000000000000102030405060708030000000000000000000000000000000000000000000000000099999999999999999999999999999999f020586a82fabf8ca1ac5fec5566c76e5ce8600005868d409729c0969464e994"
AuthorizationDigest2 :: "be2e0e353a304bb521ee46856a99cb1f7ae6550af56568e0d00b99922d0da5fe"
AuthorizationHead2 :: "c2aba25f511968747ae2c51e8c68b65e85ffb42c598cbc25263bd0c9391bc993"

@(test)
authorization_decisions_match_golden_and_expiry_boundary :: proc(t: ^testing.T) {
	events_hex := [3]string{AuthorizationEvent0, AuthorizationEvent1, AuthorizationEvent2}
	digests_hex := [3]string{AuthorizationDigest0, AuthorizationDigest1, AuthorizationDigest2}
	heads_hex := [3]string{AuthorizationHead0, AuthorizationHead1, AuthorizationHead2}
	for event_hex, index in events_hex {
		expected := vector_bytes(event_hex)
		defer delete(expected)
		expected_digest := vector_bytes(digests_hex[index])
		defer delete(expected_digest)
		expected_head := vector_bytes(heads_hex[index])
		defer delete(expected_head)
		value := audit.AuthorizationRecorded{recorded_time = 0x0001020304050607, expected_control_revision = 0x0807060504030201, decision = audit.AuthorizationDecision(index+1)}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 3
		value.proposal = {store = value.reference.store, epoch = 1, sequence = 2}
		for &byte in value.evidence { byte = 0x99 }
		copy(value.previous_head[:], expected[138:])
		if value.decision == .Permit {
			for &byte in value.capability { byte = 0x88 }
			value.expiry = 0x0102030405060708
			value.use_limit = 1
		}
		encoded, err := audit.encode_authorization_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_authorization_recorded(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_authorization_recorded(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 3, previous_sequence = 2, previous_head = value.previous_head, digest = digest})
		testing.expect_value(t, string(head[:]), string(expected_head))
		value.expected_control_revision = 0
		if value.decision == .Permit { value.expiry = value.recorded_time+1 }
		encoded, err = audit.encode_authorization_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		decoded, decode_error = audit.decode_authorization_recorded(encoded[:], value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
	}
}

@(test)
authorization_rejects_invalid_decision_fields_and_references :: proc(t: ^testing.T) {
	vectors := [3]string{AuthorizationEvent0, AuthorizationEvent1, AuthorizationEvent2}
	store: events.StoreId
	for &byte in store { byte = 1 }
	for text, index in vectors {
		bytes := vector_bytes(text)
		defer delete(bytes)
		value, _ := audit.decode_authorization_recorded(bytes, store, 1)
		invalid_values := [3]audit.AuthorizationRecorded{value,value,value}
		wire: [3]audit.AuthorizationRecordedBytes
		for &item in wire { copy(item[:], bytes) }
		errors := [3]audit.Error{.Malformed,.Malformed,.Malformed}
		if index == 0 {
			invalid_values[0].capability = {}
			invalid_values[1].expiry = value.recorded_time
			invalid_values[2].use_limit = 0
			for &byte in wire[0][97:113] { byte = 0 }
			assert(endian.put_u64(wire[1][113:121], .Little, value.recorded_time))
			wire[2][121] = 0
			errors[0] = .InvalidIdentity
		} else {
			invalid_values[0].capability[0] = 1
			invalid_values[1].expiry = 1
			invalid_values[2].use_limit = 1
			wire[0][97], wire[1][113], wire[2][121] = 1, 1, 1
		}
		for invalid, field in invalid_values {
			_, err := audit.encode_authorization_recorded(invalid, store, 1)
			testing.expect_value(t, err, errors[field])
			rejected, decode_error := audit.decode_authorization_recorded(wire[field][:], store, 1)
			testing.expect_value(t, decode_error, errors[field])
			testing.expect_value(t, rejected, audit.AuthorizationRecorded{})
		}
	}
	golden := vector_bytes(AuthorizationEvent0)
	defer delete(golden)
	base: audit.AuthorizationRecordedBytes
	copy(base[:], golden)
	decisions := [2]u8{0,4}
	for decision in decisions {
		changed := base
		changed[96] = decision
		_, err := audit.decode_authorization_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .Unsupported)
	}
	zero_ids := [2]int{56,122}
	for offset in zero_ids {
		changed := base
		for &byte in changed[offset:offset+16] { byte = 0 }
		_, err := audit.decode_authorization_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .InvalidIdentity)
	}
	changed := base
	changed[56] = 2
	_, err := audit.decode_authorization_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	changed = base
	changed[72] = 2
	_, err = audit.decode_authorization_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	sequences := [3]u8{0,3,4}
	expected_errors := [3]audit.Error{.InvalidIdentity,.Malformed,.Malformed}
	for sequence, index in sequences {
		changed = base
		changed[80] = sequence
		_, err = audit.decode_authorization_recorded(changed[:], store, 1)
		testing.expect_value(t, err, expected_errors[index])
	}
	proposal := vector_bytes(ProposalEvent0)
	defer delete(proposal)
	_, err = audit.decode_authorization_recorded(proposal, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_proposal_recorded(golden, store, 1)
	testing.expect_value(t, err, .Malformed)
	changed = base
	changed[48] = 1
	_, err = audit.decode_authorization_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .Unsupported)
}
