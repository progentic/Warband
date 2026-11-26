package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

CapabilityRevoked0_event_hex :: "574245560100090001010101010101010101010101010101010000000000000004000000000000000806050403020100020001003a00000001010101010101010101010101010101010000000000000003000000000000008888888888888888888888888888888802020304050607080c0014aebf797b39d30c13cee72bebecb1d5e6be6426550eee74b5165f30966bb095"
CapabilityRevoked0_event_digest :: "3768df446838144d915a686e730f79156633d24e9007b489a35ccb400a80533c"
CapabilityRevoked0_head :: "65d16e804c0ecdabb03fd92018172340f066ed56c9735aba76bf6a8460bb7755"

@(test)
capability_revoked_matches_golden :: proc(t: ^testing.T) {
	vectors := [?]string{CapabilityRevoked0_event_hex}
	digests := [?]string{CapabilityRevoked0_event_digest}
	heads := [?]string{CapabilityRevoked0_head}
	previous := vector_bytes(AuthorizationHead0)
	defer delete(previous)
	for text, index in vectors {
		expected := vector_bytes(text)
		defer delete(expected)
		value := audit.CapabilityRevoked{recorded_time = 0x1020304050608, expected_control_revision = 0x807060504030202, reason = 12}
		for &byte in value.reference.store { byte = 1 }
		value.reference.epoch = 1
		value.reference.sequence = 4
		value.authorization = {value.reference.store, 1, 3}
		copy(value.previous_head[:], previous)
		for &byte in value.capability { byte = 0x88 }
		encoded, err := audit.encode_capability_revoked(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded[:]), string(expected))
		decoded, decode_error := audit.decode_capability_revoked(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_capability_revoked(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		expected_digest := vector_bytes(digests[index])
		defer delete(expected_digest)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 4, previous_sequence = 3, previous_head = value.previous_head, digest = digest})
		expected_head := vector_bytes(heads[index])
		defer delete(expected_head)
		testing.expect_value(t, string(head[:]), string(expected_head))
		value.expected_control_revision = 0
		limits := [2]u16{1, 13}
		for reason in limits {
			value.reason = reason
			encoded, err = audit.encode_capability_revoked(value, value.reference.store, 1)
			testing.expect_value(t, err, .None)
			decoded, decode_error = audit.decode_capability_revoked(encoded[:], value.reference.store, 1)
			testing.expect_value(t, decode_error, .None)
			testing.expect_value(t, decoded, value)
		}
	}
}

@(test)
capability_revoked_rejects_invalid_fields :: proc(t: ^testing.T) {
	golden := vector_bytes(CapabilityRevoked0_event_hex)
	defer delete(golden)
	base: audit.CapabilityRevokedBytes
	copy(base[:], golden)
	store: events.StoreId
	copy(store[:], base[8:24])
	other := vector_bytes(AttemptDisposition0_event_hex)
	defer delete(other)
	_, cross_error := audit.decode_capability_revoked(other, store, 1)
	testing.expect_value(t, cross_error, .Malformed)
	mutations := [?]struct{offset: int, replacement: u8, error: audit.Error}{
		{6, 10, .Unsupported}, {48, 1, .Unsupported}, {52, 0, .Malformed}, {56, 2, .InvalidIdentity},
		{72, 2, .InvalidIdentity}, {80, 0, .InvalidIdentity}, {80, 4, .Malformed}, {80, 5, .Malformed},
		{112, 0, .Unsupported}, {112, 14, .Unsupported},
	}
	for mutation in mutations {
		changed := base
		changed[mutation.offset] = mutation.replacement
		rejected, err := audit.decode_capability_revoked(changed[:], store, 1)
		testing.expect_value(t, err, mutation.error)
		testing.expect_value(t, rejected, audit.CapabilityRevoked{})
	}
	for &byte in base[88:104] { byte = 0 }
	_, err := audit.decode_capability_revoked(base[:], store, 1)
	testing.expect_value(t, err, .InvalidIdentity)
}
