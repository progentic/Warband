package audit_test

import "core:testing"
import a "../../../src/audit"
import c "../../../src/custody"
import e "../../../src/domain/events"

// Literal ADR-0009 bytes with the independently reproduced fingerprint and heads.
MarkerProposalHex :: "5742455602000b0001010101010101010101010101010101010000000000000002000000000000000a00000000000000010001008600000002020202020202020202020202020202030303030303030303030303030303030404040404040404040404040404040405050505050505050505050505050505060606060606060606060606060606060800000000000000090000000000000001000000000000000000000000000000020000000000000002000102000101030000006162635555555555555555555555555555555555555555555555555555555555555555"
MarkerApprovalHex :: "5742455602000c0001010101010101010101010101010101010000000000000003000000000000000b00000000000000060001007d0000000101010101010101010101010101010101000000000000000200000000000000da7e15ffea6ade7f21c3fc1996871787aee98bae7919fe25bf4a9ed7bf3c2f7b03000000ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ade8030000000000000107070707070707070707070707070707102f9fa2a7a24c949afa3babf50320392441b8fd7faa99cd6a5cfec9a57a5851"
MarkerFingerprint :: "da7e15ffea6ade7f21c3fc1996871787aee98bae7919fe25bf4a9ed7bf3c2f7b"
MarkerDisplay :: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
MarkerProposalHead :: "102f9fa2a7a24c949afa3babf50320392441b8fd7faa99cd6a5cfec9a57a5851"
MarkerApprovalDigest :: "b590294fb37319e3779ae82b0f952d80d4bf34f34a0853b8066fcb5f5e9196b1"
MarkerApprovalHead :: "fa52b1686a1a434cee736e1053130cfc041f340cbb03defd3c382b296d746e7a"

marker_hash :: proc(s: string) -> (result: [32]u8) {
	b := vector_bytes(s)
	defer delete(b)
	assert(len(b)==32)
	copy(result[:],b)
	return
}

marker_pair :: proc() -> (p: a.MarkerProposal, approval: a.MarkerApproval) {
	p.reference.epoch, p.reference.sequence, p.recorded_time = 1,2,10
	p.device,p.inode,p.expected_task_version,p.length = 8,9,1,3
	copy(p.payload[:],"abc")
	for i in 0..<16 {
		p.reference.store[i],p.task[i],p.run[i],p.proposal[i] = 1,2,3,4
		p.attempt[i],p.directory[i],approval.evidence[i] = 5,6,7
	}
	for &b in p.previous_head { b = 0x55 }
	approval.reference,approval.proposal = p.reference,p.reference
	approval.reference.sequence = 3
	approval.recorded_time,approval.operator_uid,approval.display_length,approval.decision = 11,1000,3,.Approve
	approval.previous_head = marker_hash(MarkerProposalHead)
	approval.fingerprint,approval.display_digest = marker_hash(MarkerFingerprint),marker_hash(MarkerDisplay)
	return
}

@(test)
marker_linked_golden_records :: proc(t: ^testing.T) {
	p,approval := marker_pair()
	store := p.reference.store
	pb := vector_bytes(MarkerProposalHex); defer delete(pb)
	ab := vector_bytes(MarkerApprovalHex); defer delete(ab)
	encoded,pe := a.encode_marker_proposal(p,store,1)
	signed,ae := a.encode_marker_approval(approval,store,1)
	testing.expect(t,pe==.None && ae==.None && encoded.length==222 && len(signed)==213)
	testing.expect(t,string(encoded.data[:encoded.length])==string(pb) && string(signed[:])==string(ab))
	decoded,pd := a.decode_marker_proposal(pb,store,1)
	decision,ad := a.decode_marker_approval(ab,store,1)
	testing.expect(t,pd==.None && decoded==p && ad==.None && decision==approval)
	fp,h,he := a.marker_proposal_hashes(decoded,store,1)
	testing.expect(t,he==.None && fp==marker_hash(MarkerFingerprint) && h==marker_hash(MarkerDisplay))
	digest,de := a.digest_marker_proposal(decoded,store,1)
	link := e.Pledge{store=store,epoch=1,sequence=2,previous_sequence=1,previous_head=p.previous_head,digest=digest}
	testing.expect(t,de==.None && c.derive_head(link)==marker_hash(MarkerProposalHead))
	link.sequence,link.previous_sequence,link.previous_head = 3,2,decision.previous_head
	link.digest,de = a.digest_marker_approval(decision,store,1)
	testing.expect(t,de==.None && link.digest==marker_hash(MarkerApprovalDigest) && c.derive_head(link)==marker_hash(MarkerApprovalHead))
	testing.expect(t,a.marker_approval_matches(decision,decoded,store,1))
}

@(test)
marker_payload_length_bounds :: proc(t: ^testing.T) {
	p,approval := marker_pair()
	store := p.reference.store
	for n in ([?]u32{0,4096}) {
		p.length = n
		p.payload = {}
		if n>0 { p.payload[n-1] = '\n' }
		wire,err := a.encode_marker_proposal(p,store,1)
		testing.expect(t,err==.None && wire.length==219+int(n))
		back,decoded := a.decode_marker_proposal(wire.data[:wire.length],store,1)
		testing.expect(t,decoded==.None && back==p)
		approval.display_length = n
		approval.fingerprint,approval.display_digest,err = a.marker_proposal_hashes(p,store,1)
		testing.expect(t,err==.None && a.marker_approval_matches(approval,p,store,1))
		if n==0 { testing.expect_value(t,approval.display_digest,marker_hash("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) }
	}
	p.length = 4097
	_,err := a.encode_marker_proposal(p,store,1)
	testing.expect(t,err==.Malformed && !a.marker_approval_matches(approval,p,store,1))
	// Consistent envelope and inner lengths for an otherwise valid 4097-byte payload.
	oversized: [219+4097]u8
	small := vector_bytes(MarkerProposalHex); defer delete(small)
	copy(oversized[:187],small[:187])
	copy(oversized[len(oversized)-32:],small[len(small)-32:])
	oversized[52],oversized[53],oversized[183],oversized[184] = 0x84,0x10,1,0x10
	_,err = a.decode_marker_proposal(oversized[:],store,1)
	testing.expect_value(t,err,.Malformed)
}

@(test)
marker_malformed_framing :: proc(t: ^testing.T) {
	decode_error :: proc(bytes: []u8, store: e.StoreId, proposal: bool) -> a.Error {
		if proposal {
			_,err := a.decode_marker_proposal(bytes,store,1)
			return err
		}
		_,err := a.decode_marker_approval(bytes,store,1)
		return err
	}
	p,_ := marker_pair()
	for text,i in ([?]string{MarkerProposalHex,MarkerApprovalHex}) {
		b := vector_bytes(text); defer delete(b)
		for offset in ([?]int{0,4,6,48,50,52}) {
			b[offset] ~= 1
			testing.expect(t,decode_error(b,p.reference.store,i==0)!=.None)
			b[offset] ~= 1
		}
		long := make([]u8,len(b)+1); defer delete(long)
		copy(long,b)
		for invalid in ([?][]u8{nil,b[:87],b[:len(b)-1],long}) {
			testing.expect(t,decode_error(invalid,p.reference.store,i==0)!=.None)
		}
	}
}

@(test)
marker_approval_withholds_on_mutation :: proc(t: ^testing.T) {
	p,approval := marker_pair()
	store := p.reference.store
	b := vector_bytes(MarkerProposalHex); defer delete(b)
	// Valid substitutions must reach the binding check, including the same-length payload change.
	for offset in ([?]int{32,56,72,88,104,120,136,144,152,160,187}) {
		b[offset] ~= 3
		other,err := a.decode_marker_proposal(b,store,1)
		testing.expect(t,err==.None && !a.marker_approval_matches(approval,other,store,1))
		b[offset] ~= 3
	}
	for offset in ([?]int{8,24,168,176,178,179,181,182,183,186}) {
		b[offset] ~= 1
		_,err := a.decode_marker_proposal(b,store,1)
		testing.expect(t,err!=.None)
		b[offset] ~= 1
	}
	changed_payload := p
	changed_payload.payload[1] ~= 1
	altered_display := approval
	_,new_display,hash_error := a.marker_proposal_hashes(changed_payload,store,1)
	altered_display.display_digest = new_display
	testing.expect(t,hash_error==.None && !a.marker_approval_matches(altered_display,changed_payload,store,1))
	ab := vector_bytes(MarkerApprovalHex); defer delete(ab)
	for offset in ([?]int{80,88,120,124}) {
		ab[offset] ~= 3
		changed,err := a.decode_marker_approval(ab,store,1)
		testing.expect(t,err==.None && !a.marker_approval_matches(changed,p,store,1))
		ab[offset] ~= 3
	}
	ab[164] = 2
	rejected,err := a.decode_marker_approval(ab,store,1)
	testing.expect(t,err==.None && rejected.decision==.Reject && !a.marker_approval_matches(rejected,p,store,1))
	for offset in ([?]int{56,72,80,123,164}) {
		old := ab[offset]
		ab[offset] = 255
		_,invalid := a.decode_marker_approval(ab,store,1)
		testing.expect(t,invalid!=.None)
		ab[offset] = old
	}
}
