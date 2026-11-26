package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

#assert(events.AttemptId != events.CapabilityId)
// Independently reproduced encoding example following the permit's own Ref.
DispatchEvent :: "57424556010004000101010101010101010101010101010101000000000000000400000000000000090807060504030002000100780000000101010101010101010101010101010101000000000000000300000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa8888888888888888888888888888888801000000000000000202030405060708c2406d9f939ac81bf762471f3ef5d5c985f844ee46bce010232b1afbdb57a679080706050403020014aebf797b39d30c13cee72bebecb1d5e6be6426550eee74b5165f30966bb095"
DispatchDigest :: "01651b7cbf79dbd75a0723c81bf8103eb4ded9870e08632fe5744c5d019129f0"
DispatchHead :: "939bc65ad26b3879a6240292cd026150c3b8c956ce94e17a37e57e8a5ef0a6ba"
DispatchFingerprint :: "c2406d9f939ac81bf762471f3ef5d5c985f844ee46bce010232b1afbdb57a679"

@(test)
dispatch_claimed_matches_golden_and_representation_bounds :: proc(t: ^testing.T) {
	expected := vector_bytes(DispatchEvent)
	defer delete(expected)
	expected_digest := vector_bytes(DispatchDigest)
	defer delete(expected_digest)
	expected_head := vector_bytes(DispatchHead)
	defer delete(expected_head)
	fingerprint := vector_bytes(DispatchFingerprint)
	defer delete(fingerprint)
	value := audit.DispatchClaimed{recorded_time = 0x0003040506070809, claim_time = 0x0002030405060708, expected_task_version = 1, expected_control_revision = 0x0807060504030202}
	for &byte in value.reference.store { byte = 1 }
	value.reference.epoch = 1
	value.reference.sequence = 4
	value.authorization = {store = value.reference.store, epoch = 1, sequence = value.reference.sequence-1}
	for &byte in value.attempt { byte = 0xaa }
	for &byte in value.capability { byte = 0x88 }
	copy(value.proposal_fingerprint[:], fingerprint)
	copy(value.previous_head[:], expected[176:])
	encoded, err := audit.encode_dispatch_claimed(value, value.reference.store, 1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(encoded[:]), string(expected))
	decoded, decode_error := audit.decode_dispatch_claimed(expected, value.reference.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	digest, digest_error := audit.digest_dispatch_claimed(value, value.reference.store, 1)
	testing.expect_value(t, digest_error, .None)
	testing.expect_value(t, string(digest[:]), string(expected_digest))
	head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 4, previous_sequence = 3, previous_head = value.previous_head, digest = digest})
	testing.expect_value(t, string(head[:]), string(expected_head))
	// Representation-only cases: these do not assert a coherent post-permit history.
	value.expected_control_revision = 0
	value.proposal_fingerprint = {}
	claim_times := [2]u64{0, max(u64)}
	for claim_time in claim_times {
		value.claim_time = claim_time
		candidate, candidate_error := audit.encode_dispatch_claimed(value, value.reference.store, 1)
		testing.expect_value(t, candidate_error, .None)
		roundtrip, roundtrip_error := audit.decode_dispatch_claimed(candidate[:], value.reference.store, 1)
		testing.expect_value(t, roundtrip_error, .None)
		testing.expect_value(t, roundtrip, value)
	}
	value.authorization.sequence = value.reference.sequence
	_, err = audit.encode_dispatch_claimed(value, value.reference.store, 1)
	testing.expect_value(t, err, .Malformed)
}

@(test)
dispatch_claimed_rejects_invalid_references_and_payload :: proc(t: ^testing.T) {
	expected := vector_bytes(DispatchEvent)
	defer delete(expected)
	authorization := vector_bytes(AuthorizationEvent0)
	defer delete(authorization)
	store: events.StoreId
	for &byte in store { byte = 1 }
	base: audit.DispatchClaimedBytes
	copy(base[:], expected)
	zero_identity_offsets := [3]int{56,88,104}
	for offset in zero_identity_offsets {
		changed := base
		for &byte in changed[offset:offset+16] { byte = 0 }
		invalid, identity_error := audit.decode_dispatch_claimed(changed[:], store, 1)
		testing.expect_value(t, identity_error, .InvalidIdentity)
		testing.expect_value(t, invalid, audit.DispatchClaimed{})
	}
	changed := base
	changed[56] = 2
	_, err := audit.decode_dispatch_claimed(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	changed = base
	changed[72] = 2
	_, err = audit.decode_dispatch_claimed(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	sequences := [3]u8{0,4,5}
	errors := [3]audit.Error{.InvalidIdentity,.Malformed,.Malformed}
	for sequence, index in sequences {
		changed = base
		changed[80] = sequence
		_, err = audit.decode_dispatch_claimed(changed[:], store, 1)
		testing.expect_value(t, err, errors[index])
	}
	changed = base
	changed[120] = 0
	_, err = audit.decode_dispatch_claimed(changed[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	changed = base
	changed[52] = 119
	_, err = audit.decode_dispatch_claimed(changed[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	changed = base
	changed[48] = 1
	_, err = audit.decode_dispatch_claimed(changed[:], store, 1)
	testing.expect_value(t, err, .Unsupported)
	_, err = audit.decode_dispatch_claimed(authorization, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_authorization_recorded(expected, store, 1)
	testing.expect_value(t, err, .Malformed)
}
