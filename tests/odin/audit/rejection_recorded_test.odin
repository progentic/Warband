package audit_test

import "core:testing"
import "../../../src/audit"
import "../../../src/custody"
import "../../../src/domain/events"

Rejection0_event_hex :: "5742455601000800010101010101010101010101010101010100000000000000030000000000000001000000000000000200010044000000020800010101010101010101010101010101010101000000000000000200000000000000f644e2abb3c06acb5da33f656fed54cbf5b08bb729ae67ef1dee32f8a231862ff020586a82fabf8ca1ac5fec5566c76e5ce8600005868d409729c0969464e994"
Rejection0_head :: "cd8fbcbee7832541c3bca571b2d6e5dfa5c0111ef95e1604a598712189d286b1"
Rejection0_event_digest :: "2ba568d77df20f34c28063a49749b54c445e70a37f386dd83d67b78fb189ec84"
Rejection0_input :: "f644e2abb3c06acb5da33f656fed54cbf5b08bb729ae67ef1dee32f8a231862f"
Rejection1_event_hex :: "5742455601000800010101010101010101010101010101010100000000000000030000000000000001000000000000000500010024000000070d0000700eb3d2b18b9f2ea70ec86dac4fb2a007b322e311c3129e2b07c5bfa252f805f020586a82fabf8ca1ac5fec5566c76e5ce8600005868d409729c0969464e994"
Rejection1_head :: "9c9d231f5b0c06077eadf5d3554cd7906554a875d89fdcae65bf824de1c8455b"
Rejection1_event_digest :: "430839a8c5801942bb1e779c7e52a6e024d35b8b3c5c4578bc04d7663c7127a3"
Rejection1_input :: "700eb3d2b18b9f2ea70ec86dac4fb2a007b322e311c3129e2b07c5bfa252f805"

@(test)
rejection_recorded_matches_golden_and_stage_assignments :: proc(t: ^testing.T) {
	vectors := [?]string{Rejection0_event_hex, Rejection1_event_hex}
	digests := [?]string{Rejection0_event_digest, Rejection1_event_digest}
	heads := [?]string{Rejection0_head, Rejection1_head}
	inputs := [?]string{Rejection0_input, Rejection1_input}
	previous := vector_bytes(ProposalHead1)
	defer delete(previous)
	value := audit.RejectionRecorded{recorded_time = 1}
	for &byte in value.reference.store { byte = 1 }
	value.reference.epoch = 1
	value.reference.sequence = 3
	copy(value.previous_head[:], previous)
	for text, index in vectors {
		expected := vector_bytes(text)
		defer delete(expected)
		input := vector_bytes(inputs[index])
		defer delete(input)
		copy(value.rejected_input_digest[:], input)
		if index == 0 {
			value.producer, value.stage, value.reason = 2, 2, 8
			value.related = events.EventRef{value.reference.store, 1, 2}
		} else {
			value.producer, value.stage, value.reason = 5, 7, 13
			value.related = nil
		}
		encoded, err := audit.encode_rejection_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded.data[:encoded.length]), string(expected))
		for byte in encoded.data[encoded.length:] { testing.expect_value(t, byte, u8(0)) }
		decoded, decode_error := audit.decode_rejection_recorded(expected, value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
		digest, digest_error := audit.digest_rejection_recorded(value, value.reference.store, 1)
		testing.expect_value(t, digest_error, .None)
		expected_digest := vector_bytes(digests[index])
		defer delete(expected_digest)
		testing.expect_value(t, string(digest[:]), string(expected_digest))
		head := custody.derive_head({store = value.reference.store, epoch = 1, sequence = 3, previous_sequence = 2, previous_head = value.previous_head, digest = digest})
		expected_head := vector_bytes(heads[index])
		defer delete(expected_head)
		testing.expect_value(t, string(head[:]), string(expected_head))
	}
	assignments := [?]struct{producer: u16, stage: u8}{{1,1},{2,2},{2,3},{3,4},{4,5},{5,6},{5,7}}
	for pair in assignments {
		value.producer, value.stage = pair.producer, pair.stage
		encoded, err := audit.encode_rejection_recorded(value, value.reference.store, 1)
		testing.expect_value(t, err, .None)
		decoded, decode_error := audit.decode_rejection_recorded(encoded.data[:encoded.length], value.reference.store, 1)
		testing.expect_value(t, decode_error, .None)
		testing.expect_value(t, decoded, value)
	}
}

@(test)
rejection_recorded_rejects_invalid_tags_roles_and_refs :: proc(t: ^testing.T) {
	present := vector_bytes(Rejection0_event_hex)
	defer delete(present)
	absent := vector_bytes(Rejection1_event_hex)
	defer delete(absent)
	store: events.StoreId
	copy(store[:], present[8:24])
	mutations := [?]struct{offset: int, byte: u8, error: audit.Error}{
		{48,1,.Unsupported}, {48,6,.Unsupported}, {56,8,.Unsupported},
		{57,0,.Unsupported}, {57,14,.Unsupported}, {59,0,.Malformed}, {59,2,.Malformed},
		{60,2,.InvalidIdentity}, {76,2,.InvalidIdentity}, {84,0,.InvalidIdentity},
		{84,3,.Malformed}, {84,4,.Malformed}, {52,36,.Malformed}, {6,7,.Unsupported},
	}
	for mutation in mutations {
		changed: [156]u8
		copy(changed[:], present)
		changed[mutation.offset] = mutation.byte
		rejected, err := audit.decode_rejection_recorded(changed[:], store, 1)
		testing.expect_value(t, err, mutation.error)
		testing.expect_value(t, rejected, audit.RejectionRecorded{})
	}
	absent[59] = 1
	_, err := audit.decode_rejection_recorded(absent, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_rejection_recorded(present[:155], store, 1)
	testing.expect_value(t, err, .Malformed)
	other := vector_bytes(DispatchEvent)
	defer delete(other)
	_, err = audit.decode_rejection_recorded(other, store, 1)
	testing.expect_value(t, err, .Malformed)
	_, err = audit.decode_dispatch_claimed(present, store, 1)
	testing.expect_value(t, err, .Malformed)
}
