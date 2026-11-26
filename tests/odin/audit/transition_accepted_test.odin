package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

TransitionAccepted0_event_hex :: "574245560100070001010101010101010101010101010101010000000000000007000000000000000c08070605040300050001006900000001010101010101010101010101010101010000000000000006000000000000000101010101010101010101010101010101000000000000000400000000000000dddddddddddddddddddddddddddddddd010000000000000003020304050607080200000000000000026211a9c32c5fb0634e089da74fb207f0b4b625db7c375d67301088d4d3f4e411"
TransitionAccepted0_event_digest :: "c43e0863bbc85ef8684048cf7a32d571a581561cc186ce35f47cfc729239412f"
TransitionAccepted0_head :: "579cfc5a68d7b28a3d2f1a6227b12570789ca1ec326c14f04ed16adf7c4acdb5"

@(test)
transition_accepted_matches_golden :: proc(t: ^testing.T) {
	expected := vector_bytes(TransitionAccepted0_event_hex)
	defer delete(expected)
	value := audit.TransitionAccepted{recorded_time = 0x000304050607080c, expected_task_version = 1, expected_control_revision = 0x0807060504030203}
	for &byte in value.reference.store { byte = 1 }
	value.reference.epoch = 1
	value.reference.sequence = 7
	value.evaluation = {value.reference.store, 1, 6}
	value.claim = {value.reference.store, 1, 4}
	for &byte in value.transition { byte = 0xdd }
	previous_head := vector_bytes(EvaluationRecorded0_head)
	defer delete(previous_head)
	copy(value.previous_head[:], previous_head)
	encoded, err := audit.encode_transition_accepted(value, value.reference.store, 1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, string(encoded[:]), string(expected))
	decoded, decode_error := audit.decode_transition_accepted(expected, value.reference.store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	digest, digest_error := audit.digest_transition_accepted(value, value.reference.store, 1)
	testing.expect_value(t, digest_error, .None)
	expected_digest := vector_bytes(TransitionAccepted0_event_digest)
	defer delete(expected_digest)
	testing.expect_value(t, string(digest[:]), string(expected_digest))
	head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = value.reference.sequence, previous_sequence = value.reference.sequence-1, previous_head = value.previous_head, digest = digest})
	expected_head := vector_bytes(TransitionAccepted0_head)
	defer delete(expected_head)
	testing.expect_value(t, string(head[:]), string(expected_head))
}

@(test)
transition_accepted_rejects_invalid_fields :: proc(t: ^testing.T) {
	golden := vector_bytes(TransitionAccepted0_event_hex)
	defer delete(golden)
	base: audit.TransitionAcceptedBytes
	copy(base[:], golden)
	store: events.StoreId
	copy(store[:], base[8:24])
	invalid := [9]struct{offset: int, replacement: u8, error: audit.Error}{
		{48, 4, .Unsupported}, {52, 104, .Malformed}, {72, 2, .InvalidIdentity},
		{88, 2, .InvalidIdentity}, {80, 7, .Malformed}, {112, 6, .Malformed},
		{136, 0, .Malformed}, {152, 3, .Malformed}, {160, 1, .Unsupported},
	}
	for mutation in invalid {
		changed := base
		changed[mutation.offset] = mutation.replacement
		rejected, err := audit.decode_transition_accepted(changed[:], store, 1)
		testing.expect_value(t, err, mutation.error)
		testing.expect_value(t, rejected, audit.TransitionAccepted{})
	}
	changed := base
	for &byte in changed[120:136] { byte = 0 }
	_, err := audit.decode_transition_accepted(changed[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
	value, _ := audit.decode_transition_accepted(golden, store, 1)
	value.expected_task_version = max(u64)-1
	encoded, encode_error := audit.encode_transition_accepted(value, store, 1)
	testing.expect_value(t, encode_error, .None)
	decoded, decode_error := audit.decode_transition_accepted(encoded[:], store, 1)
	testing.expect_value(t, decode_error, .None)
	testing.expect_value(t, decoded, value)
	value.expected_task_version = max(u64)
	_, err = audit.encode_transition_accepted(value, store, 1)
	testing.expect_value(t, err, .Malformed)
	for &byte in encoded[136:144] { byte = 0xff }
	for &byte in encoded[152:160] { byte = 0 }
	_, err = audit.decode_transition_accepted(encoded[:], store, 1)
	testing.expect_value(t, err, .Malformed)
}
