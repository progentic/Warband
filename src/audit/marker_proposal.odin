package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerPayloadLimit :: 4096
MarkerProposalFixedSize :: 131
MarkerProposalDomain :: "warband.marker.proposal.v1\x00"
DirectoryId :: distinct [16]u8

MarkerProposal :: struct {
	reference: e.EventRef,
	recorded_time: u64,
	task: e.TaskId,
	run: e.RunId,
	proposal: e.ProposalId,
	attempt: e.AttemptId,
	directory: DirectoryId,
	device, inode, expected_task_version, expected_control_revision: u64,
	length: u32,
	payload: [MarkerPayloadLimit]u8,
	previous_head: [32]u8,
}
MarkerProposalEncoding :: struct {
	data: [88+MarkerProposalFixedSize+MarkerPayloadLimit]u8,
	length: int,
}

// Create marker, private directory, approved marker criterion, stop/reconcile, approval required.
@(private)
MarkerShape :: "\x02\x00\x01\x02\x00\x01\x01"

@(private)
validate_marker_proposal :: proc(p: MarkerProposal, store: e.StoreId, epoch: e.Epoch) -> Error {
	if e.validate_event_ref(p.reference,store,epoch) != .None || p.task == (e.TaskId{}) ||
	   p.run == (e.RunId{}) || p.proposal == (e.ProposalId{}) || p.attempt == (e.AttemptId{}) ||
	   p.directory == (DirectoryId{}) { return .InvalidIdentity }
	if p.length > MarkerPayloadLimit || p.expected_task_version == 0 { return .Malformed }
	return .None
}

encode_marker_proposal :: proc(p: MarkerProposal, store: e.StoreId, epoch: e.Epoch) -> (MarkerProposalEncoding, Error) {
	if err := validate_marker_proposal(p,store,epoch); err != .None { return {},err }
	p := p
	result := MarkerProposalEncoding{length=88+MarkerProposalFixedSize+int(p.length)}
	b := result.data[:result.length]
	write_envelope(b,{p.reference,p.recorded_time,p.previous_head},11,1,2)
	copy(b[56:72],p.task[:])
	copy(b[72:88],p.run[:])
	copy(b[88:104],p.proposal[:])
	copy(b[104:120],p.attempt[:])
	copy(b[120:136],p.directory[:])
	assert(endian.put_u64(b[136:144],.Little,p.device))
	assert(endian.put_u64(b[144:152],.Little,p.inode))
	assert(endian.put_u64(b[152:160],.Little,p.expected_task_version))
	assert(endian.put_u64(b[160:168],.Little,p.expected_control_revision))
	assert(endian.put_u64(b[168:176],.Little,2))
	copy(b[176:183],MarkerShape)
	assert(endian.put_u32(b[183:187],.Little,p.length))
	copy(b[187:result.length-32],p.payload[:p.length])
	return result,.None
}

decode_marker_proposal :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerProposal, Error) {
	if len(b) < 88+MarkerProposalFixedSize || len(b) > 88+MarkerProposalFixedSize+MarkerPayloadLimit {
		return {},.Malformed
	}
	env,err := read_envelope(b,11,1,len(b)-88,2)
	if err != .None { return {},err }
	n,_ := endian.get_u32(b[183:187],.Little)
	if n != u32(len(b)-88-MarkerProposalFixedSize) { return {},.Malformed }
	policy,_ := endian.get_u64(b[168:176],.Little)
	if policy != 2 || string(b[176:183]) != MarkerShape { return {},.Unsupported }
	p := MarkerProposal{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,length=n}
	copy(p.task[:],b[56:72])
	copy(p.run[:],b[72:88])
	copy(p.proposal[:],b[88:104])
	copy(p.attempt[:],b[104:120])
	copy(p.directory[:],b[120:136])
	p.device,_ = endian.get_u64(b[136:144],.Little)
	p.inode,_ = endian.get_u64(b[144:152],.Little)
	p.expected_task_version,_ = endian.get_u64(b[152:160],.Little)
	p.expected_control_revision,_ = endian.get_u64(b[160:168],.Little)
	if invalid := validate_marker_proposal(p,store,epoch); invalid != .None { return {},invalid }
	copy(p.payload[:n],b[187:len(b)-32])
	return p,.None
}

marker_proposal_hashes :: proc(p: MarkerProposal, store: e.StoreId, epoch: e.Epoch) -> (fingerprint, display_digest: [32]u8, err: Error) {
	wire,issue := encode_marker_proposal(p,store,epoch)
	if issue != .None { return {},{},issue }
	body := wire.data[:wire.length-32]
	return hash_event_data(MarkerProposalDomain,body[8:40],body[56:]),hash_event_data("",body[187:]),.None
}

digest_marker_proposal :: proc(p: MarkerProposal, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	wire,err := encode_marker_proposal(p,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,wire.data[:wire.length-32]),.None
}
