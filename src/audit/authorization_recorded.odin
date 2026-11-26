package audit

import "../domain/events"
import "core:encoding/endian"

AuthorizationDecision :: enum u8 {Permit = 1, Reject = 2, RequireApproval = 3}
AuthorizationRecorded :: struct {
	reference: events.EventRef,
	recorded_time: u64,
	proposal: events.EventRef,
	expected_control_revision: u64,
	decision: AuthorizationDecision,
	capability: events.CapabilityId,
	expiry: u64,
	use_limit: u8,
	evidence: events.EvidenceId,
	previous_head: [32]u8,
}
AuthorizationRecordedBytes :: [170]u8
AuthorizationRecordedBodySize :: 138

encode_authorization_recorded :: proc(value: AuthorizationRecorded, store: events.StoreId, epoch: events.Epoch) -> (AuthorizationRecordedBytes, Error) {
	value := value
	if err := validate_authorization_recorded(value, store, epoch); err != .None {
		return {}, err
	}
	bytes: AuthorizationRecordedBytes
	write_envelope(bytes[:], {value.reference, value.recorded_time, value.previous_head}, 3, 2)
	copy(bytes[56:72], value.proposal.store[:])
	assert(endian.put_u64(bytes[72:80], .Little, u64(value.proposal.epoch)))
	assert(endian.put_u64(bytes[80:88], .Little, u64(value.proposal.sequence)))
	assert(endian.put_u64(bytes[88:96], .Little, value.expected_control_revision))
	bytes[96] = u8(value.decision)
	copy(bytes[97:113], value.capability[:])
	assert(endian.put_u64(bytes[113:121], .Little, value.expiry))
	bytes[121] = value.use_limit
	copy(bytes[122:138], value.evidence[:])
	return bytes, .None
}

decode_authorization_recorded :: proc(bytes: []u8, store: events.StoreId, epoch: events.Epoch) -> (AuthorizationRecorded, Error) {
	envelope, err := read_envelope(bytes, 3, 2, 82)
	if err != .None {
		return {}, err
	}
	if bytes[96] < 1 || bytes[96] > 3 {
		return {}, .Unsupported
	}
	value := AuthorizationRecorded{reference = envelope.reference, recorded_time = envelope.recorded_time, previous_head = envelope.previous_head, decision = AuthorizationDecision(bytes[96]), use_limit = bytes[121]}
	copy(value.proposal.store[:], bytes[56:72])
	proposal_epoch, _ := endian.get_u64(bytes[72:80], .Little)
	proposal_sequence, _ := endian.get_u64(bytes[80:88], .Little)
	value.proposal.epoch = events.Epoch(proposal_epoch)
	value.proposal.sequence = events.Sequence(proposal_sequence)
	value.expected_control_revision, _ = endian.get_u64(bytes[88:96], .Little)
	copy(value.capability[:], bytes[97:113])
	value.expiry, _ = endian.get_u64(bytes[113:121], .Little)
	copy(value.evidence[:], bytes[122:138])
	if validation_error := validate_authorization_recorded(value, store, epoch); validation_error != .None {
		return {}, validation_error
	}
	return value, .None
}

digest_authorization_recorded :: proc(value: AuthorizationRecorded, store: events.StoreId, epoch: events.Epoch) -> ([32]u8, Error) {
	bytes, err := encode_authorization_recorded(value, store, epoch)
	if err != .None {
		return {}, err
	}
	return hash_event_data(EventDomain, bytes[:AuthorizationRecordedBodySize]), .None
}

@(private)
validate_authorization_recorded :: proc(value: AuthorizationRecorded, store: events.StoreId, epoch: events.Epoch) -> Error {
	if value.decision != .Permit && value.decision != .Reject && value.decision != .RequireApproval {
		return .Unsupported
	}
	if events.validate_event_ref(value.reference, store, epoch) != .None || events.validate_event_ref(value.proposal, store, epoch) != .None {
		return .InvalidIdentity
	}
	if value.proposal.sequence >= value.reference.sequence {
		return .Malformed
	}
	empty_evidence := events.EvidenceId{}
	empty_capability := events.CapabilityId{}
	if value.evidence == empty_evidence {
		return .InvalidIdentity
	}
	if value.decision == .Permit {
		if value.capability == empty_capability {
			return .InvalidIdentity
		}
		if value.expiry <= value.recorded_time || value.use_limit != 1 {
			return .Malformed
		}
	} else if value.capability != empty_capability || value.expiry != 0 || value.use_limit != 0 {
		return .Malformed
	}
	return .None
}
