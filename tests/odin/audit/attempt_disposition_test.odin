package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

AttemptDisposition0_event_hex :: "5742455601000a0001010101010101010101010101010101010000000000000005000000000000000a08070605040300050001002b00000001010101010101010101010101010101010000000000000004000000000000000302030405060708010a00939bc65ad26b3879a6240292cd026150c3b8c956ce94e17a37e57e8a5ef0a6ba"
AttemptDisposition0_event_digest :: "8195db64f69c674cac2aefc2e4a8d0f55db522852cd085d616c84a8b8e6f2e20"
AttemptDisposition0_head :: "08f1dbddcc8085387b686d47fd6af5c966dbad24a421ea6c5701f8be2526f95d"
AttemptDisposition1_event_hex :: "5742455601000a0001010101010101010101010101010101010000000000000005000000000000000a08070605040300050001002b00000001010101010101010101010101010101010000000000000004000000000000000302030405060708020c00939bc65ad26b3879a6240292cd026150c3b8c956ce94e17a37e57e8a5ef0a6ba"
AttemptDisposition1_event_digest :: "7be1b2fb3d2e2827290dc26859bf4aa98e989bc2bdfc4164e437987a18c56d55"
AttemptDisposition1_head :: "effaea217cc9596798c35359f47353624ffe55e5f25335c052472c5c8c022b3c"

@(test)
attempt_disposition_matches_golden :: proc(t: ^testing.T) {
	vectors := [?]string{AttemptDisposition0_event_hex, AttemptDisposition1_event_hex}
	digests := [?]string{AttemptDisposition0_event_digest, AttemptDisposition1_event_digest}
	heads := [?]string{AttemptDisposition0_head, AttemptDisposition1_head}
	previous := vector_bytes(DispatchHead)
	defer delete(previous)
	for text, index in vectors {
		expected := vector_bytes(text)
		defer delete(expected)
		value := audit.AttemptDisposition{recorded_time = 0x304050607080a, expected_control_revision = 0x807060504030203, reason = 12}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 5
		value.claim = {value.reference.store, 1, 4}
		copy(value.previous_head[:], previous)
		value.disposition = audit.Disposition(index+1)
		if value.disposition == .Indeterminate { value.reason = 10 }
		encoded, err := audit.encode_attempt_disposition(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_attempt_disposition(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_attempt_disposition(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		expected_digest := vector_bytes(digests[index])
		defer delete(expected_digest)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 5, previous_sequence = 4, previous_head = value.previous_head, digest = digest})
		expected_head := vector_bytes(heads[index])
		defer delete(expected_head)
		testing.expect_value(t, string(head[:]), string(expected_head))
		value.expected_control_revision = 0
		limits := [2]u16{1, 13}
		for reason in limits {
			value.reason = reason
			encoded, err = audit.encode_attempt_disposition(value, value.reference.store, 1)
			testing.expect_value(t, err, .None)
			decoded, decode_error = audit.decode_attempt_disposition(encoded[:], value.reference.store, 1)
			testing.expect_value(t, decode_error, .None)
			testing.expect_value(t, decoded, value)
		}
	}
}

@(test)
attempt_disposition_rejects_invalid_fields :: proc(t: ^testing.T) {
	golden := vector_bytes(AttemptDisposition0_event_hex)
	defer delete(golden)
	base: audit.AttemptDispositionBytes
	copy(base[:], golden)
	store: events.StoreId
	copy(store[:], base[8:24])
	other := vector_bytes(CapabilityRevoked0_event_hex)
	defer delete(other)
	_, cross_error := audit.decode_attempt_disposition(other, store, 1)
	testing.expect_value(t, cross_error, .Malformed)
	mutations := [?]struct{offset: int, replacement: u8, error: audit.Error}{
		{6, 9, .Unsupported}, {48, 1, .Unsupported}, {52, 0, .Malformed}, {56, 2, .InvalidIdentity},
		{72, 2, .InvalidIdentity}, {80, 0, .InvalidIdentity}, {80, 5, .Malformed}, {80, 6, .Malformed},
		{97, 0, .Unsupported}, {97, 14, .Unsupported}, {96, 0, .Unsupported}, {96, 3, .Unsupported},
	}
	for mutation in mutations {
		changed := base
		changed[mutation.offset] = mutation.replacement
		rejected, err := audit.decode_attempt_disposition(changed[:], store, 1)
		testing.expect_value(t, err, mutation.error)
		testing.expect_value(t, rejected, audit.AttemptDisposition{})
	}
}
