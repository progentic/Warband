package audit

import e "../domain/events"
import "core:encoding/endian"

MarkerDelivery :: enum u8 {ReplyReceived=1, ReplyLost, DeadlineReached, ProcessFailure, Unknown}
MarkerEntry :: enum u8 {Unassessed, Absent, Regular, Nonregular, Oversized, InspectionIncomplete}
MarkerObservation :: struct {
	reference, claim: e.EventRef,
	recorded_time: u64,
	evidence: e.EvidenceId,
	delivery: MarkerDelivery,
	worker_stopped, directory_control: bool,
	entry: MarkerEntry,
	observed_length: u64,
	observed_hash, previous_head: [32]u8,
}
MarkerObservationBytes :: [180]u8

@(private)
validate_marker_observation :: proc(v: MarkerObservation, store: e.StoreId, epoch: e.Epoch) -> Error {
	if v.evidence == (e.EvidenceId{}) { return .InvalidIdentity }
	if v.delivery < .ReplyReceived || v.delivery > .Unknown || v.entry > .InspectionIncomplete { return .Unsupported }
	if (v.worker_stopped && v.directory_control) != (v.entry != .Unassessed) { return .Malformed }
	switch v.entry {
	case .Regular:
		if v.observed_length > MarkerPayloadLimit { return .Malformed }
		if v.observed_length == 0 && v.observed_hash != hash_event_data("",nil) { return .Malformed }
	case .Oversized:
		if v.observed_length <= MarkerPayloadLimit || v.observed_hash != ([32]u8{}) { return .Malformed }
	case .Unassessed,.Absent,.Nonregular,.InspectionIncomplete:
		if v.observed_length != 0 || v.observed_hash != ([32]u8{}) { return .Malformed }
	}
	return validate_marker_predecessor(v.reference,v.claim,store,epoch)
}

encode_marker_observation :: proc(v: MarkerObservation, store: e.StoreId, epoch: e.Epoch) -> (MarkerObservationBytes, Error) {
	if err := validate_marker_observation(v,store,epoch); err != .None { return {},err }
	v := v
	b: MarkerObservationBytes
	write_envelope(b[:],{v.reference,v.recorded_time,v.previous_head},15,7,2)
	write_ref(b[56:88],v.claim)
	copy(b[88:104],v.evidence[:])
	b[104],b[105],b[106],b[107] = u8(v.delivery),u8(v.worker_stopped),u8(v.directory_control),u8(v.entry)
	assert(endian.put_u64(b[108:116],.Little,v.observed_length))
	copy(b[116:148],v.observed_hash[:])
	return b,.None
}

decode_marker_observation :: proc(b: []u8, store: e.StoreId, epoch: e.Epoch) -> (MarkerObservation, Error) {
	env,err := read_envelope(b,15,7,92,2)
	if err != .None { return {},err }
	if b[105] > 1 || b[106] > 1 { return {},.Malformed }
	v := MarkerObservation{reference=env.reference,recorded_time=env.recorded_time,previous_head=env.previous_head,
	                       claim=read_ref(b[56:88]),delivery=MarkerDelivery(b[104]),worker_stopped=b[105]==1,
	                       directory_control=b[106]==1,entry=MarkerEntry(b[107])}
	copy(v.evidence[:],b[88:104])
	v.observed_length,_ = endian.get_u64(b[108:116],.Little)
	copy(v.observed_hash[:],b[116:148])
	if invalid := validate_marker_observation(v,store,epoch); invalid != .None { return {},invalid }
	return v,.None
}

digest_marker_observation :: proc(v: MarkerObservation, store: e.StoreId, epoch: e.Epoch) -> ([32]u8, Error) {
	b,err := encode_marker_observation(v,store,epoch)
	if err != .None { return {},err }
	return hash_event_data(EventDomain,b[:len(b)-32]),.None
}
