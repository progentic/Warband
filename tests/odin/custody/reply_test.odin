package custody_test

import "core:testing"
import "core:encoding/endian"
import "../../../src/custody"

Reply_base :: "5742525301000300008a000000a5679f0f1d58d5ed8997b25fcb0bba7418c458ed3214f976b088f62bd7af2a27000000000000000000000000000000000000000000000000000000000000000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd1800030000000000000000"
Reply_pending :: "57425253010003000012010000a5679f0f1d58d5ed8997b25fcb0bba7418c458ed3214f976b088f62bd7af2a27000000000000000000000000000000000000000000000000000000000000000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd180101010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035030000000000000000"
Reply_rejection :: "57425253010003000055010000600a8c131ec5348f800106ffe8c91037dce7c714dad114d51a22fc4f1b2c4062000000000000000000000000000000000000000000000000000000000000000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd1800030000000000000001574243480100055800000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005e5afbc47563ec9417ce8285ab50c75f6e6cf05227447a41d5591d6aca4b258c70101010101010101010101010101010101000000000000000f0000000000002de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af01e903000000000000e9030000000000002a00000000000000ee18da5b6b035d42ec9e9c994a11078e6a51b7a00854c23793c78cc2ca1777d2"
Reply_both :: "574252530100030000dd010000600a8c131ec5348f800106ffe8c91037dce7c714dad114d51a22fc4f1b2c4062000000000000000000000000000000000000000000000000000000000000000001010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd180101010101010101010101010101010101010000000000000000000000000000004108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72fe77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035030000000000000001574243480100055800000003000000000000008ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005e5afbc47563ec9417ce8285ab50c75f6e6cf05227447a41d5591d6aca4b258c70101010101010101010101010101010101000000000000000f0000000000002de8ff7b25bd809b55240a887d96600c6dd2f0babd233808163a3085216391af01e903000000000000e9030000000000002a00000000000000ee18da5b6b035d42ec9e9c994a11078e6a51b7a00854c23793c78cc2ca1777d2"
Reply_denied :: "574252530100030f008a000000a5679f0f1d58d5ed8997b25fcb0bba7418c458ed3214f976b088f62bd7af2a27ee18da5b6b035d42ec9e9c994a11078e6a51b7a00854c23793c78cc2ca1777d20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
Reply_storage_fault :: "574252530100030e008a000000a5679f0f1d58d5ed8997b25fcb0bba7418c458ed3214f976b088f62bd7af2a2700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

@(private)
verify_context :: proc(cursor: u64, authenticated: bool) -> custody.ReplyContext {
	store := genesis_value().store
	request := custody.Request{.Verify, custody.VerifyRequest{store, 1, cursor}}
	digest, err := custody.digest_request(request, store, 1)
	assert(err == .None)
	return {authenticated, .Verify, digest, store, 1, cursor}
}

@(test)
custody_reply_shapes_and_redaction_match_vectors :: proc(t: ^testing.T) {
	vectors := [?]string{Reply_base, Reply_pending, Reply_rejection, Reply_both, Reply_denied, Reply_storage_fault}
	pledge := golden_pledge(golden_bytes())
	raw := literal_bytes(RejectionFrame)
	defer delete(raw)
	frame: custody.RejectionFrameBytes
	copy(frame[:], raw)
	for text, index in vectors {
		with_pending := index == 1 || index == 3
		with_frame := index == 2 || index == 3
		cursor: u64 = 3
		if with_frame { cursor = 2 }
		ctx := verify_context(cursor, index < 4)
		value := custody.Reply{status = .Ready, tip = 3, committed = {pledge.store, 1, 0, pledge.previous_head}}
		if with_pending { value.pending = pledge }
		if with_frame { value.rejection = frame }
		if !ctx.authenticated {
			value.status = .CustodianAuthFault
			if index == 4 { copy(value.receipt[:], raw[171:]) }
			if index == 5 { value.status = .CheckpointStorageFault }
			// Supply all protected fields: encoder must remove them before writing bytes.
			value.pending = pledge
			value.rejection = frame
		}
		expected := literal_bytes(text)
		defer delete(expected)
		encoded, err := custody.encode_reply(value, ctx)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, string(encoded.data[:encoded.length]), string(expected))
		for byte in encoded.data[encoded.length:] { testing.expect_value(t, byte, u8(0)) }
		decoded, decode_err := custody.decode_reply(expected, ctx)
		testing.expect_value(t, decode_err, .None)
		if !ctx.authenticated {
			value.pending = nil
			value.rejection = nil
			value.committed = {}
			value.tip = 0
		}
		testing.expect_value(t, decoded, value)
	}
}

@(test)
custody_reply_rejects_disclosure_and_invalid_framing :: proc(t: ^testing.T) {
	ctx := verify_context(3, false)
	base := literal_bytes(Reply_denied)
	defer delete(base)
	protected_offsets := [?]int{77,93,101,109,142}
	for offset in protected_offsets {
		base[offset] = 1
		rejected, err := custody.decode_reply(base, ctx)
		testing.expect_value(t, err, .Malformed)
		testing.expect_value(t, rejected, custody.Reply{})
		base[offset] = 0
	}
	options := [?]string{Reply_pending, Reply_rejection}
	for text in options {
		wire := literal_bytes(text)
		defer delete(wire)
		wire[7] = 15
		for &byte in wire[77:141] { byte = 0 }
		tip_offset := len(wire)-9
		if len(wire) == 354 { tip_offset -= 203 }
		for &byte in wire[tip_offset:tip_offset+8] { byte = 0 }
		cursor: u64 = 3
		if len(wire) == 354 { cursor = 2 }
		_, err := custody.decode_reply(wire, verify_context(cursor, false))
		testing.expect_value(t, err, .Malformed)
	}
	base[7] = 14
	_, err := custody.decode_reply(base, ctx)
	testing.expect_value(t, err, .Malformed)
	base[7] = 0
	_, err = custody.decode_reply(base, ctx)
	testing.expect_value(t, err, .Malformed)
	base[7] = 15
	_, err = custody.decode_reply(base[:150], ctx)
	testing.expect_value(t, err, .Malformed)
	fields := [?]struct{offset: int, byte: u8, error: custody.FormatError}{
		{0,0,.Malformed}, {4,2,.Unsupported}, {6,6,.Unsupported}, {6,1,.Malformed},
		{7,20,.Unsupported}, {9,0,.Malformed}, {13,0,.Malformed},
		{141,1,.Malformed}, {141,2,.Malformed}, {150,1,.Malformed}, {150,2,.Malformed},
	}
	for f in fields {
		saved := base[f.offset]
		base[f.offset] = f.byte
		_, got := custody.decode_reply(base, ctx)
		testing.expect_value(t, got, f.error)
		base[f.offset] = saved
	}
}

@(test)
custody_reply_binds_verify_receipt_to_cursor_and_tip :: proc(t: ^testing.T) {
	wire := literal_bytes(Reply_rejection)
	defer delete(wire)
	ctx := verify_context(2, true)
	value, err := custody.decode_reply(wire, ctx)
	testing.expect_value(t, err, .None)
	// ordinal == tip is included; ordinal == cursor is excluded.
	ctx.after_ordinal = 3
	_, err = custody.decode_reply(wire, ctx)
	testing.expect_value(t, err, .InvalidOrdinal)
	ctx.after_ordinal = 2
	value.tip = 2
	_, err = custody.encode_reply(value, ctx)
	testing.expect_value(t, err, .InvalidOrdinal)
	value.tip = 3
	ctx.operation = .Prepare
	_, err = custody.encode_reply(value, ctx)
	testing.expect_value(t, err, .Malformed)
	ctx.operation = .Verify
	value.status = .CheckpointConflict
	_, err = custody.encode_reply(value, ctx)
	testing.expect_value(t, err, .Malformed)
	wire[151+6] = 1
	_, err = custody.decode_reply(wire, ctx)
	testing.expect_value(t, err, .Malformed)
	wire[151+6] = 5
	wire[len(wire)-1] ~= 1
	_, err = custody.decode_reply(wire, ctx)
	testing.expect_value(t, err, .AttestationHistoryFault)
	base := literal_bytes(Reply_base)
	defer delete(base)
	ctx = verify_context(3, true)
	assert(endian.put_u64(base[142:150], .Little, 2))
	_, err = custody.decode_reply(base, ctx)
	testing.expect_value(t, err, .InvalidOrdinal)
}
