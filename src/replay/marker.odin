package replay

import a "../audit"
import e "../domain/events"
import state "../state"

// Retain the validated binding and hashes, while the decoder owns the bounded payload temporarily.
@(private)
MarkerProposalSummary :: struct {
	key: Key,
	proposal: e.ProposalId,
	attempt: e.AttemptId,
	directory: a.DirectoryId,
	task_version, control_revision: u64,
	length: u32,
	fingerprint, payload_hash: [32]u8,
}
@(private)
MarkerApprovalSummary :: struct {
	proposal: e.EventRef,
	fingerprint, display_digest: [32]u8,
	length: u32,
	decision: a.MarkerDecision,
	evidence: e.EvidenceId,
}
@(private)
decode_marker :: proc(b: []u8,ref: e.EventRef,kind: u16) -> (Event,bool) {
	switch kind {
	case 11:
		v,err := a.decode_marker_proposal(b,ref.store,ref.epoch)
		if err!=.None || v.reference!=ref { return nil,false }
		f,d,issue := a.marker_proposal_hashes(v,ref.store,ref.epoch)
		return MarkerProposalSummary{{v.task,v.run},v.proposal,v.attempt,v.directory,v.expected_task_version,
		                             v.expected_control_revision,v.length,f,d},issue==.None
	case 12:
		v,err := a.decode_marker_approval(b,ref.store,ref.epoch)
		return MarkerApprovalSummary{v.proposal,v.fingerprint,v.display_digest,v.display_length,v.decision,v.evidence},err==.None && v.reference==ref
	case 13:
		v,err := a.decode_marker_permit(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 14:
		v,err := a.decode_marker_claim(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 15:
		v,err := a.decode_marker_observation(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 16:
		v,err := a.decode_marker_evaluation(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 17:
		v,err := a.decode_marker_accepted(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	}
	return nil,false
}

@(private)
MarkerChain :: struct {
	slot: int,
	view: Projection,
	approval,permit,claim,observation,evaluation: e.Sequence,
	capability: e.CapabilityId,
}

@(private)
MarkerLedger :: struct {
	roots: map[e.Sequence]e.Sequence, // marker event sequence to its proposal
	chains: map[e.Sequence]MarkerChain,
	latest: map[int]e.Sequence, // task slot to its most recently projected marker chain
}

@(private)
observed_verdict :: proc(obs: a.MarkerObservation, approval: MarkerApprovalSummary) -> a.MarkerVerdict {
	if obs.worker_stopped && obs.directory_control {
		if obs.entry==.Absent { return .Incomplete }
		if obs.entry==.Regular && obs.observed_length==u64(approval.length) && obs.observed_hash==approval.display_digest {
			return .Verified
		}
	}
	return .OperatorReconciliation
}

@(private)
apply_marker :: proc(m: ^MarkerLedger,records: []Record,i: int,by_key: map[Key]int,states: []state.Evidence,
                     ids: ^map[ScopedId]bool) -> (handled: bool, issue: Error) {
	rec := records[i]
	seq := e.Sequence(i+1)
	root,prior: e.Sequence
	#partial switch v in rec.event {
	case MarkerProposalSummary:
		root = seq
		slot := by_key[v.key]
		if slot==0 { return true,.InvalidReference }
		h := &states[slot-1]
		if h.task_version!=v.task_version ||
		   h.control_revision!=v.control_revision || !unique(ids,.Proposal,cast([16]u8)v.proposal) ||
		   !unique(ids,.Attempt,cast([16]u8)v.attempt) || !unique(ids,.Directory,cast([16]u8)v.directory) {
			return true,.InvalidHistory
		}
		if map_insert(&m.chains,root,MarkerChain{slot=slot,view={marker=true}})==nil { return true,.ResourceLimit }
	case MarkerApprovalSummary: prior = v.proposal.sequence
	case a.MarkerPermit: prior = v.approval.sequence
	case a.MarkerClaim: prior = v.permit.sequence
	case a.MarkerObservation: prior = v.claim.sequence
	case a.MarkerEvaluation: prior = v.observation.sequence
	case a.MarkerAccepted: prior = v.evaluation.sequence
	case a.CapabilityRevoked:
		prior = v.authorization.sequence
		if m.roots[prior]==0 { return false,.None }
	case a.AttemptDisposition:
		prior = v.claim.sequence
		if m.roots[prior]==0 { return false,.None }
	case: return false,.None
	}
	if prior!=0 { root = m.roots[prior] }
	if root==0 { return true,.InvalidReference }
	chain := &m.chains[root]
	h := &states[chain.slot-1]
	p := &chain.view
	prop := records[root-1].event.(MarkerProposalSummary)
	if h.transition!=nil || m.chains[m.latest[chain.slot]].view.complete { return true,.InvalidHistory }
	#partial switch v in rec.event {
	case MarkerApprovalSummary:
		if prior!=root { return true,.InvalidReference }
		if chain.approval!=0 || v.fingerprint!=prop.fingerprint || v.length!=prop.length || v.display_digest!=prop.payload_hash ||
		   h.task_version!=prop.task_version || h.control_revision!=prop.control_revision ||
		   !unique(ids,.Evidence,cast([16]u8)v.evidence) { return true,.InvalidHistory }
		chain.approval,p.approval = seq,v.decision
	case a.MarkerPermit:
		if prior!=chain.approval { return true,.InvalidReference }
		if p.approval!=.Approve || chain.permit!=0 || v.expected_control_revision!=h.control_revision ||
		   h.control_revision!=prop.control_revision || h.task_version!=prop.task_version ||
		   !unique(ids,.Capability,cast([16]u8)v.capability) || !unique(ids,.Evidence,cast([16]u8)v.evidence) { return true,.InvalidHistory }
		chain.permit,chain.capability,p.authorization = seq,v.capability,u8(a.AuthorizationDecision.Permit)
		h.control_revision += 1
	case a.MarkerClaim:
		if prior!=chain.permit { return true,.InvalidReference }
		if p.revoked || chain.claim!=0 || v.capability!=chain.capability || v.attempt!=prop.attempt || v.fingerprint!=prop.fingerprint ||
		   v.expected_task_version!=h.task_version || h.task_version!=prop.task_version ||
		   v.expected_control_revision!=h.control_revision || h.control_revision-1!=prop.control_revision { return true,.InvalidHistory }
		chain.claim,p.attempt,p.consumed = seq,v.attempt,true
		h.control_revision += 1
	case a.MarkerObservation:
		if prior!=chain.claim { return true,.InvalidReference }
		if chain.observation!=0 || !unique(ids,.Evidence,cast([16]u8)v.evidence) { return true,.InvalidHistory }
		chain.observation = seq
		p.observation,p.delivery = u8(v.entry),v.delivery
	case a.MarkerEvaluation:
		if prior!=chain.observation || v.claim.sequence!=chain.claim { return true,.InvalidReference }
		observation := records[prior-1]
		approval := records[chain.approval-1].event.(MarkerApprovalSummary)
		expected := observed_verdict(observation.event.(a.MarkerObservation),approval)
		if chain.evaluation!=0 || v.observation_digest!=observation.digest || v.verdict!=expected ||
		   !unique(ids,.Evidence,cast([16]u8)v.evidence) { return true,.InvalidHistory }
		chain.evaluation,p.verdict = seq,u8(v.verdict)
	case a.MarkerAccepted:
		if prior!=chain.evaluation || v.claim.sequence!=chain.claim { return true,.InvalidReference }
		if !p.consumed || p.revoked || p.disposition!=0 || p.verdict!=u8(a.MarkerVerdict.Verified) ||
		   v.expected_task_version!=h.task_version || h.task_version!=prop.task_version ||
		   v.expected_control_revision!=h.control_revision || h.control_revision-2!=prop.control_revision ||
		   !unique(ids,.Transition,cast([16]u8)v.transition) { return true,.InvalidHistory }
		p.complete = true
		h.task_version += 1
		h.control_revision += 1
	case a.CapabilityRevoked:
		if prior!=chain.permit { return true,.InvalidReference }
		if p.revoked || v.capability!=chain.capability || v.expected_control_revision!=h.control_revision ||
		   h.control_revision==max(u64) { return true,.InvalidHistory }
		p.revoked = true
		h.control_revision += 1
	case a.AttemptDisposition:
		if prior!=chain.claim { return true,.InvalidReference }
		if p.disposition!=0 || v.expected_control_revision!=h.control_revision || h.control_revision==max(u64) { return true,.InvalidHistory }
		p.disposition,p.disposition_reason = u8(v.disposition),v.reason
		h.control_revision += 1
	}
	if map_insert(&m.roots,seq,root)==nil || map_insert(&m.latest,chain.slot,root)==nil { return true,.ResourceLimit }
	return true,.None
}
