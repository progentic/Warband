package audit_test

import "core:encoding/endian"
import "core:testing"
import a "../../../src/audit"
import c "../../../src/custody"
import e "../../../src/domain/events"

vector_ref :: proc(sequence: e.Sequence) -> (r: e.EventRef) {
	r.epoch,r.sequence = 1,sequence
	for &b in r.store { b = 1 }
	return
}

vector_id :: proc($T: typeid, byte: u8) -> (id: T) {
	for &b in id { b = byte }
	return
}

check_marker_vector :: proc(t: ^testing.T, v: $T, vector: MarkerVector,
		encode: proc(T,e.StoreId,e.Epoch) -> ($B,a.Error),
		decode: proc([]u8,e.StoreId,e.Epoch) -> (T,a.Error),
		digest: proc(T,e.StoreId,e.Epoch) -> ([32]u8,a.Error)) {
	store := v.reference.store
	wire := vector_bytes(vector.wire)
	defer delete(wire)
	encoded,err := encode(v,store,1)
	testing.expect(t,err==.None && string(encoded[:])==string(wire))
	decoded,issue := decode(wire,store,1)
	testing.expect(t,issue==.None && decoded==v)
	d,hash_err := digest(decoded,store,1)
	testing.expect(t,hash_err==.None && d==marker_hash(vector.digest))
	link := e.Pledge{store=store,epoch=1,sequence=v.reference.sequence,previous_sequence=v.reference.sequence-1,
	                 previous_head=v.previous_head,digest=d}
	testing.expect_value(t,c.derive_head(link),marker_hash(vector.head))
}

// Decoding the literals also checks field interpretation independently of encoding.
@(test)
marker_evidence_linked_goldens :: proc(t: ^testing.T) {
	permit := a.MarkerPermit{reference=vector_ref(4),approval=vector_ref(3),recorded_time=12,
	                         capability=vector_id(e.CapabilityId,8),evidence=vector_id(e.EvidenceId,9),
	                         expected_control_revision=0,audit_expiry=90000012,previous_head=marker_hash(MarkerApprovalHead)}
	check_marker_vector(t,permit,MarkerEvidenceVectors[0],a.encode_marker_permit,a.decode_marker_permit,a.digest_marker_permit)
	claim := a.MarkerClaim{reference=vector_ref(5),permit=permit.reference,recorded_time=13,attempt=vector_id(e.AttemptId,5),
	                       capability=permit.capability,expected_task_version=1,expected_control_revision=1,
	                       fingerprint=marker_hash(MarkerFingerprint),previous_head=marker_hash(MarkerEvidenceVectors[0].head)}
	check_marker_vector(t,claim,MarkerEvidenceVectors[1],a.encode_marker_claim,a.decode_marker_claim,a.digest_marker_claim)
	obs := a.MarkerObservation{reference=vector_ref(6),claim=claim.reference,recorded_time=14,evidence=vector_id(e.EvidenceId,10),
	                           delivery=.ReplyLost,worker_stopped=true,directory_control=true,entry=.Regular,observed_length=3,
	                           observed_hash=marker_hash(MarkerDisplay),previous_head=marker_hash(MarkerEvidenceVectors[1].head)}
	check_marker_vector(t,obs,MarkerEvidenceVectors[2],a.encode_marker_observation,a.decode_marker_observation,a.digest_marker_observation)
	eval := a.MarkerEvaluation{reference=vector_ref(7),observation=obs.reference,claim=claim.reference,recorded_time=15,
	                           observation_digest=marker_hash(MarkerEvidenceVectors[2].digest),verdict=.Verified,
	                           evidence=vector_id(e.EvidenceId,11),previous_head=marker_hash(MarkerEvidenceVectors[2].head)}
	check_marker_vector(t,eval,MarkerEvidenceVectors[3],a.encode_marker_evaluation,a.decode_marker_evaluation,a.digest_marker_evaluation)
	accepted := a.MarkerAccepted{reference=vector_ref(8),evaluation=eval.reference,claim=claim.reference,recorded_time=16,
	                             transition=vector_id(e.TransitionId,12),expected_task_version=1,expected_control_revision=2,
	                             previous_head=marker_hash(MarkerEvidenceVectors[3].head)}
	check_marker_vector(t,accepted,MarkerEvidenceVectors[4],a.encode_marker_accepted,a.decode_marker_accepted,a.digest_marker_accepted)
}

check_marker_framing :: proc(t: ^testing.T, vector: MarkerVector, refs, ids: []int,
		decode: proc([]u8,e.StoreId,e.Epoch) -> ($T,a.Error)) {
	wire := vector_bytes(vector.wire)
	defer delete(wire)
	store := vector_ref(1).store
	padding := make([]u8,len(wire)+1)
	defer delete(padding)
	copy(padding,wire)
	for bytes in ([?][]u8{nil,wire[:87],wire[:len(wire)-1],padding}) {
		v,err := decode(bytes,store,1)
		testing.expect(t,err!=.None && v==T{})
	}
	for pos in ([?]int{0,4,6,48,50,52,8,24}) {
		wire[pos] ~= 1
		_,err := decode(wire,store,1)
		testing.expect(t,err!=.None)
		wire[pos] ~= 1
	}
	for off in refs {
		for pos in ([?]int{off,off+16}) {
			wire[pos] ~= 1
			_,err := decode(wire,store,1)
			testing.expect_value(t,err,.InvalidIdentity)
			wire[pos] ~= 1
		}
		old := wire[off+24]
		for seq in ([?]u8{0,wire[32],wire[32]+1}) {
			wire[off+24] = seq
			_,err := decode(wire,store,1)
			testing.expect(t,err!=.None)
		}
		wire[off+24] = old
	}
	for off in ids {
		saved: [16]u8
		copy(saved[:],wire[off:off+16])
		for &b in wire[off:off+16] { b=0 }
		_,err := decode(wire,store,1)
		testing.expect_value(t,err,.InvalidIdentity)
		copy(wire[off:off+16],saved[:])
	}
}

@(test)
marker_evidence_framing_and_reference_order :: proc(t: ^testing.T) {
	check_marker_framing(t,MarkerEvidenceVectors[0],{56},{88,121},a.decode_marker_permit)
	check_marker_framing(t,MarkerEvidenceVectors[1],{56},{88,104},a.decode_marker_claim)
	check_marker_framing(t,MarkerEvidenceVectors[2],{56},{88},a.decode_marker_observation)
	check_marker_framing(t,MarkerEvidenceVectors[3],{56,88},{155},a.decode_marker_evaluation)
	check_marker_framing(t,MarkerEvidenceVectors[4],{56,88},{120},a.decode_marker_accepted)
}

@(test)
marker_observation_class_and_proof_matrix :: proc(t: ^testing.T) {
	store := vector_ref(1).store
	empty := marker_hash("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	for kind in a.MarkerEntry {
		for stopped in ([?]bool{false,true}) {
			for control in ([?]bool{false,true}) {
				v := a.MarkerObservation{reference=vector_ref(6),claim=vector_ref(5),evidence=vector_id(e.EvidenceId,10),
				                         worker_stopped=stopped,directory_control=control,entry=kind,delivery=.ReplyLost}
				if kind==.Regular { v.observed_hash=empty }
				if kind==.Oversized { v.observed_length=4097 }
				b,err := a.encode_marker_observation(v,store,1)
				valid := (stopped && control)==(kind!=.Unassessed)
				testing.expect_value(t,err==.None,valid)
				if valid {
					back,decoded := a.decode_marker_observation(b[:],store,1)
					testing.expect(t,decoded==.None && back==v)
					if kind==.Regular { testing.expect(t,string(b[116:148])==string(empty[:])) }
					if kind==.Absent { testing.expect(t,b[107]==1 && back.observed_hash==([32]u8{})) }
				}
			}
		}
	}
	wire := vector_bytes(MarkerEvidenceVectors[2].wire)
	defer delete(wire)
	for code in 1..=5 {
		wire[104] = u8(code)
		_,err := a.decode_marker_observation(wire,store,1)
		testing.expect_value(t,err,.None)
	}
	// Start with both proofs, len=3, SHA-256("abc"); corrupt each constraint in isolation.
	for pos in ([?]int{104,105,106,107}) {
		old := wire[pos]
		wire[pos] = 255
		_,err := a.decode_marker_observation(wire,store,1)
		testing.expect(t,err!=.None)
		wire[pos] = old
	}
	for length in ([?]u64{0,4096,4097,max(u64)}) {
		assert(endian.put_u64(wire[108:116],.Little,length))
		wire[107] = 2
		_,regular := a.decode_marker_observation(wire,store,1)
		testing.expect_value(t,regular==.None,length==4096)
		wire[107] = 4
		_,oversized := a.decode_marker_observation(wire,store,1)
		testing.expect(t,oversized!=.None) // nonzero hash is illegal at every size
	}
	assert(endian.put_u64(wire[108:116],.Little,0))
	for &b in wire[116:148] { b = 0 }
	wire[107] = u8(a.MarkerEntry.Regular)
	_,empty_err := a.decode_marker_observation(wire,store,1)
	wire[107] = u8(a.MarkerEntry.Absent)
	_,absent_err := a.decode_marker_observation(wire,store,1)
	testing.expect(t,empty_err==.Malformed && absent_err==.None)
}

check_bad_field :: proc(t: ^testing.T, $index: int, pos, width: int, fill: u8,
		decode: proc([]u8,e.StoreId,e.Epoch) -> ($T,a.Error)) {
	wire := vector_bytes(MarkerEvidenceVectors[index].wire)
	defer delete(wire)
	for &b in wire[pos:pos+width] { b = fill }
	v,err := decode(wire,vector_ref(1).store,1)
	testing.expect(t,err!=.None && v==T{})
}

@(test)
marker_fixed_fields_and_version_edges :: proc(t: ^testing.T) {
	store := vector_ref(1).store
	check_bad_field(t,0,120,1,2,a.decode_marker_permit)       // use limit
	check_bad_field(t,0,104,8,255,a.decode_marker_permit)     // control overflow
	check_bad_field(t,1,120,8,0,a.decode_marker_claim)        // zero task version
	check_bad_field(t,1,128,8,255,a.decode_marker_claim)
	check_bad_field(t,2,105,1,0,a.decode_marker_observation) // regular file without stop proof
	check_bad_field(t,2,106,1,0,a.decode_marker_observation)
	check_bad_field(t,2,107,1,0,a.decode_marker_observation) // unassessed with both proofs
	check_bad_field(t,2,107,1,1,a.decode_marker_observation) // absent with reported bytes
	check_bad_field(t,3,152,2,0,a.decode_marker_evaluation)  // criterion
	check_bad_field(t,3,154,1,4,a.decode_marker_evaluation)  // verdict
	check_bad_field(t,3,112,1,6,a.decode_marker_evaluation)  // claim aliases observation
	check_bad_field(t,4,112,1,7,a.decode_marker_accepted)    // claim aliases evaluation
	check_bad_field(t,4,136,8,255,a.decode_marker_accepted)  // task overflow
	check_bad_field(t,4,144,8,255,a.decode_marker_accepted)  // control overflow
	check_bad_field(t,4,152,1,3,a.decode_marker_accepted)    // new task version differs from T+1
	check_bad_field(t,4,160,1,1,a.decode_marker_accepted)    // state
	wire := vector_bytes(MarkerEvidenceVectors[3].wire)
	defer delete(wire)
	for verdict in a.MarkerVerdict {
		wire[154] = u8(verdict)
		eval,err := a.decode_marker_evaluation(wire,store,1)
		testing.expect(t,err==.None && eval.verdict==verdict)
	}
	_,wrong_role := a.decode_evaluation_recorded(wire,store,1)
	testing.expect_value(t,wrong_role,.Unsupported)
	wire[4]=1
	_,old_version := a.decode_marker_evaluation(wire,store,1)
	testing.expect_value(t,old_version,.Unsupported)
}

@(test)
marker_nonregular_fields_withhold_bytes :: proc(t: ^testing.T) {
	store := vector_ref(1).store
	v := a.MarkerObservation{reference=vector_ref(6),claim=vector_ref(5),evidence=vector_id(e.EvidenceId,10),delivery=.Unknown}
	for kind in ([?]a.MarkerEntry{.Unassessed,.Absent,.Nonregular,.InspectionIncomplete}) {
		v.entry = kind
		v.worker_stopped,v.directory_control = kind!=.Unassessed,kind!=.Unassessed
		v.observed_length,v.observed_hash = 1,{}
		_,length_err := a.encode_marker_observation(v,store,1)
		v.observed_length,v.observed_hash[0] = 0,1
		_,hash_err := a.encode_marker_observation(v,store,1)
		testing.expect(t,length_err==.Malformed && hash_err==.Malformed)
	}
	v.entry,v.observed_hash = .Oversized,{}
	for length in ([?]u64{0,4096,4097,max(u64)}) {
		v.observed_length=length
		b,err := a.encode_marker_observation(v,store,1)
		testing.expect_value(t,err==.None,length>4096)
		if err==.None {
			back,decode_err := a.decode_marker_observation(b[:],store,1)
			testing.expect(t,decode_err==.None && back==v)
		}
	}
}
