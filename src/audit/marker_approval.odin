package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerDecision :: enum u8 {Approve = 1, Reject = 2}
MarkerApproval :: struct {
	reference, proposal: e.EventRef,
	recorded_time: u64,
	fingerprint: [32]u8,
	display_length: u32,
	display_digest: [32]u8,
	operator_uid: u64,
	decision: MarkerDecision,
	evidence: e.EvidenceId,
	previous_head: [32]u8,
}
MarkerApprovalBytes :: [213]u8

@(private)
validate_marker_approval :: proc(a: MarkerApproval, store: e.StoreId, epoch: e.Epoch) -> Error {
	if e.validate_event_ref(a.reference,store,epoch) != .None ||
	   e.validate_event_ref(a.proposal,store,epoch) != .None || a.evidence == (e.EvidenceId{}) { return .InvalidIdentity }
	if a.proposal.sequence >= a.reference.sequence || a.display_length > MarkerPayloadLimit { return .Malformed }
	if a.decision != .Approve && a.decision != .Reject { return .Unsupported }
	return .None
}

encode_marker_approval :: proc(a: MarkerApproval, store: e.StoreId, epoch: e.Epoch) -> (MarkerApprovalBytes, Error) {
	if err := validate_marker_approval(a,store,epoch); err != .None { return {},err }
	a := a
	b: MarkerApprovalBytes
	write_envelope(b[:],{a.reference,a.recorded_time,a.previous_head},12,6,2)
	write_ref(b[56:88],a.proposal)
	copy(b[88:120],a.fingerprint[:])
	assert(endian.put_u32(b[120:124],.Little,a.display_length))
	copy(b[124:156],a.display_digest[:])
	assert(endian.put_u64(b[156:164],.Little,a.operator_uid))
	b[164] = u8(a.decision)
	copy(b[165:181],a.evidence[:])
	return b,.None
}

decode_marker_approval :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerApproval, Error) {
	env,err := read_envelope(b,12,6,125,2)
	if err != .None { return {},err }
	a := MarkerApproval{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                    proposal=read_ref(b[56:88]),decision=MarkerDecision(b[164])}
	copy(a.fingerprint[:],b[88:120])
	a.display_length,_ = endian.get_u32(b[120:124],.Little)
	copy(a.display_digest[:],b[124:156])
	a.operator_uid,_ = endian.get_u64(b[156:164],.Little)
	copy(a.evidence[:],b[165:181])
	if invalid := validate_marker_approval(a,store,epoch); invalid != .None { return {},invalid }
	return a,.None
}

digest_marker_approval :: proc(a: MarkerApproval, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_approval(a,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}

// Compares the recorded binding. Operator authentication and custody belong to the caller.
marker_approval_matches :: proc(a: MarkerApproval, p: MarkerProposal, store: e.StoreId, epoch: e.Epoch) -> bool {
	if validate_marker_approval(a,store,epoch) != .None || a.decision != .Approve ||
	   a.proposal != p.reference || a.display_length != p.length { return false }
	fingerprint,display,err := marker_proposal_hashes(p,store,epoch)
	return err == .None && a.fingerprint == fingerprint && a.display_digest == display
}
