package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

// Alternative sequence-5 encoding examples, independently reproduced.
ObservationEvent0 :: "574245560100050001010101010101010101010101010101010000000000000005000000000000000a0807060504030003000100370000000101010101010101010101010101010101000000000000000400000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0101004e4f4f50939bc65ad26b3879a6240292cd026150c3b8c956ce94e17a37e57e8a5ef0a6ba"
ObservationDigest0 :: "494f7b1162a0651aad3e24cc10480e3cf81513a30203addc3811cd5094ab91bb"
ObservationHead0 :: "42cdb9a414e8cedd945baeba434ba53de34113167c5432ab2a77eff9532508bc"
ObservationEvent1 :: "574245560100050001010101010101010101010101010101010000000000000005000000000000000a0807060504030003000100370000000101010101010101010101010101010101000000000000000400000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02010000000000939bc65ad26b3879a6240292cd026150c3b8c956ce94e17a37e57e8a5ef0a6ba"
ObservationDigest1 :: "cb79e23e2bbd68206ea50510320d3aca506bc0b72bae0fa055f5e7dd3a01070f"
ObservationHead1 :: "dbadb1ccac9646aa41197ff457d486fc54d58943e0219108c1b093ff5e36c0d5"

@(test)
observation_outcomes_match_golden_and_derive_bytes :: proc(t: ^testing.T) {
	events_hex := [2]string{ObservationEvent0, ObservationEvent1}
	digests_hex := [2]string{ObservationDigest0, ObservationDigest1}
	heads_hex := [2]string{ObservationHead0, ObservationHead1}
	for text, index in events_hex {
		expected := vector_bytes(text)
		defer delete(expected)
		expected_digest := vector_bytes(digests_hex[index])
		defer delete(expected_digest)
		expected_head := vector_bytes(heads_hex[index])
		defer delete(expected_head)
		value := audit.ObservationRecorded{recorded_time = 0x000304050607080a, outcome = audit.ObservationOutcome(index+1)}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 5
		value.claim = {store = value.reference.store, epoch = 1, sequence = value.reference.sequence-1}
		for &byte in value.evidence { byte = 0xbb }
		copy(value.previous_head[:], expected[111:])
		encoded, err := audit.encode_observation_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_observation_recorded(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_observation_recorded(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 5, previous_sequence = 4, previous_head = value.previous_head, digest = digest})
		testing.expect_value(t, string(head[:]), string(expected_head))
		// Representation only: recorded time has no ordering constraint here.
		value.recorded_time = 0
		encoded, err = audit.encode_observation_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		decoded, decode_error = audit.decode_observation_recorded(encoded[:], value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
	}
}

@(test)
observation_rejects_outcome_patterns_and_invalid_references :: proc(t: ^testing.T) {
	vectors := [2]string{ObservationEvent0, ObservationEvent1}
	wrong_patterns := [2]string{"noop", "NOOP"}
	store: events.StoreId
	for &byte in store { byte = 1 }
	for text, index in vectors {
		expected := vector_bytes(text)
		defer delete(expected)
		base: audit.ObservationRecordedBytes
		copy(base[:], expected)
		changed := base
		copy(changed[107:111], wrong_patterns[index])
		rejected, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .Malformed)
		testing.expect_value(t, rejected, audit.ObservationRecorded{})
		for position in 0..<4 {
			changed = base
			changed[107+position] ~= 1
			_, err = audit.decode_observation_recorded(changed[:], store, 1)
			testing.expect_value(t, err, .Malformed)
		}
	}
	expected := vector_bytes(ObservationEvent0)
	defer delete(expected)
	base: audit.ObservationRecordedBytes
	copy(base[:], expected)
	outcomes := [2]u8{0,3}
	value, _ := audit.decode_observation_recorded(expected, store, 1)
	for outcome in outcomes {
		changed := base
		changed[104] = outcome
		_, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .Unsupported)
		value.outcome = audit.ObservationOutcome(outcome)
		_, err = audit.encode_observation_recorded(value, store, 1)
		testing.expect_value(t, err, .Unsupported)
	}
	criteria := [2]u8{0,2}
	for criterion in criteria {
		changed := base
		changed[105] = criterion
		_, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .Unsupported)
	}
	zero_ids := [2]int{56,88}
	for offset in zero_ids {
		changed := base
		for &byte in changed[offset:offset+16] { byte = 0 }
		_, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .InvalidIdentity)
	}
	wrong_scope_offsets := [2]int{56,72}
	for offset in wrong_scope_offsets {
		changed := base
		changed[offset] = 2
		_, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, .InvalidIdentity)
	}
	sequences := [3]u8{0,5,6}
	errors := [3]audit.Error{.InvalidIdentity,.Malformed,.Malformed}
	for sequence, index in sequences {
		changed := base
		changed[80] = sequence
		_, err := audit.decode_observation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, errors[index])
	}
	changed := base
	changed[52] = 54
	_, err := audit.decode_observation_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .Malformed)
	changed = base
	changed[48] = 2
	_, err = audit.decode_observation_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .Unsupported)
	claim := vector_bytes(DispatchEvent)
	defer delete(claim)
	_, err = audit.decode_observation_recorded(claim, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_dispatch_claimed(expected, store, 1)
	testing.expect_value(t, err, .Malformed)
}
