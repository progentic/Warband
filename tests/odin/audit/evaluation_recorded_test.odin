package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

EvaluationRecorded0_event_hex :: "574245560100060001010101010101010101010101010101010000000000000006000000000000000b08070605040300040001007300000001010101010101010101010101010101010000000000000005000000000000000101010101010101010101010101010101000000000000000400000000000000494f7b1162a0651aad3e24cc10480e3cf81513a30203addc3811cd5094ab91bb010001cccccccccccccccccccccccccccccccc42cdb9a414e8cedd945baeba434ba53de34113167c5432ab2a77eff9532508bc"
EvaluationRecorded0_event_digest :: "262286ab3108f69df447d1e8005dc846103e61e3801a30a4ec8b0b868c61bb4f"
EvaluationRecorded0_head :: "6211a9c32c5fb0634e089da74fb207f0b4b625db7c375d67301088d4d3f4e411"
EvaluationRecorded1_event_hex :: "574245560100060001010101010101010101010101010101010000000000000006000000000000000b08070605040300040001007300000001010101010101010101010101010101010000000000000005000000000000000101010101010101010101010101010101000000000000000400000000000000cb79e23e2bbd68206ea50510320d3aca506bc0b72bae0fa055f5e7dd3a01070f010002ccccccccccccccccccccccccccccccccdbadb1ccac9646aa41197ff457d486fc54d58943e0219108c1b093ff5e36c0d5"
EvaluationRecorded1_event_digest :: "608749c6ece9fcc54040b5b3905fe76f481992e7ac5ab4de5376b4f61515a972"
EvaluationRecorded1_head :: "2f9d87d85951a62cb6b8f30720581af99ca4d24f827d4b330cdc0cdfe651d896"

@(test)
evaluation_recorded_matches_golden :: proc(t: ^testing.T) {
	vectors := [2]string{EvaluationRecorded0_event_hex, EvaluationRecorded1_event_hex}
	digests := [2]string{EvaluationRecorded0_event_digest, EvaluationRecorded1_event_digest}
	heads := [2]string{EvaluationRecorded0_head, EvaluationRecorded1_head}
	observations := [2]string{ObservationDigest0, ObservationDigest1}
	previous := [2]string{ObservationHead0, ObservationHead1}
	for text, index in vectors {
		expected := vector_bytes(text)
		defer delete(expected)
		value := audit.EvaluationRecorded{recorded_time = 0x000304050607080b, verdict = audit.EvaluationVerdict(index+1)}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 6
		value.observation = {value.reference.store, 1, 5}
		value.claim = {value.reference.store, 1, 4}
		for &byte in value.evidence { byte = 0xcc }
		observed_digest := vector_bytes(observations[index])
		defer delete(observed_digest)
		copy(value.observed_event_digest[:], observed_digest)
		previous_head := vector_bytes(previous[index])
		defer delete(previous_head)
		copy(value.previous_head[:], previous_head)
		encoded, err := audit.encode_evaluation_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_evaluation_recorded(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_evaluation_recorded(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		expected_digest := vector_bytes(digests[index])
		defer delete(expected_digest)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = value.reference.sequence, previous_sequence = value.reference.sequence-1, previous_head = value.previous_head, digest = digest})
		expected_head := vector_bytes(heads[index])
		defer delete(expected_head)
		testing.expect_value(t, string(head[:]), string(expected_head))
	}
}

@(test)
evaluation_recorded_rejects_invalid_fields :: proc(t: ^testing.T) {
	golden := vector_bytes(EvaluationRecorded0_event_hex)
	defer delete(golden)
	base: audit.EvaluationRecordedBytes
	copy(base[:], golden)
	store: events.StoreId
	copy(store[:], base[8:24])
	invalid := [10]struct{offset: int, replacement: u8, error: audit.Error}{
		{48, 3, .Unsupported}, {52, 114, .Malformed}, {56, 2, .InvalidIdentity},
		{104, 2, .InvalidIdentity}, {80, 0, .InvalidIdentity}, {80, 6, .Malformed},
		{112, 5, .Malformed}, {152, 2, .Unsupported}, {154, 0, .Unsupported}, {154, 3, .Unsupported},
	}
	for mutation in invalid {
		changed := base
		changed[mutation.offset] = mutation.replacement
		rejected, err := audit.decode_evaluation_recorded(changed[:], store, 1)
		testing.expect_value(t, err, mutation.error)
		testing.expect_value(t, rejected, audit.EvaluationRecorded{})
	}
	changed := base
	for &byte in changed[155:171] { byte = 0 }
	_, err := audit.decode_evaluation_recorded(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
}
