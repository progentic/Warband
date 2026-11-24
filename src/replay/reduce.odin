package replay

import a "../audit"
import state "../state"

@(private)
IdClass :: enum {Command, Proposal, Capability, Attempt, Evidence, Transition, Directory}
@(private)
ScopedId :: struct {kind: IdClass, bytes: [16]u8}
@(private)
unique :: proc(ids: ^map[ScopedId]bool, kind: IdClass, id: [16]u8) -> bool {
	_, ptr, existed := map_upsert(ids, ScopedId{kind,id}, true)
	return ptr!=nil && !existed
}

// The cap includes expired and earlier-epoch issuances; slots are never recycled.
RequestWitness :: struct {issued: a.RequestIssued, expiry: Maybe(a.RequestExpired)}
RequestHistory :: struct {entries: [32]RequestWitness, count: int}

find_request :: proc(h: ^RequestHistory,id: [16]u8) -> ^RequestWitness {
	for &entry in h.entries[:h.count] {
		if entry.issued.id==id { return &entry }
	}
	return nil
}

// State and IDs are scoped to the store/epoch already verified by project.
// owners maps each event position to its task slot (one-based, zero for audit only).
@(private)
reduce :: proc(records: []Record,receipts: []Receipt,$markers: bool,requests: ^RequestHistory) -> ([]Projection,int,Error) {
	when markers {
		ledger: MarkerLedger
		defer { delete(ledger.roots); delete(ledger.chains); delete(ledger.latest) }
		return reduce_records(records,receipts,true,&ledger,requests)
	} else {
		return reduce_records(records,receipts,false)
	}
}

@(private)
reduce_records :: proc(records: []Record,receipts: []Receipt,$markers: bool,marker: ^MarkerLedger = nil, requests: ^RequestHistory = nil) -> ([]Projection,int,Error) {
	owners,alloc := make([]int,len(records),context.allocator)
	if alloc!=nil { return nil,0,.ResourceLimit }
	defer delete(owners)
	by_key: map[Key]int
	ids: map[ScopedId]bool
	states: [dynamic]state.Evidence
	dispositions: [dynamic]a.AttemptDisposition
	defer delete(by_key)
	defer delete(ids)
	defer delete(states)
	defer delete(dispositions)
	used := 0
	for rec,i in records {
		slot := 0
		when markers {
			if handled,issue := apply_marker(marker,records,i,by_key,states[:],&ids); handled {
				if issue!=.None { return nil,0,issue }
				continue
			}
		}
		// All reference codecs already enforce the full scope and strictly earlier sequence.
		#partial switch v in rec.event {
		case a.RequestIssued:
			if requests==nil || find_request(requests,v.id)!=nil { return nil,0,.InvalidHistory }
			if requests.count==len(requests.entries) { return nil,0,.ResourceLimit }
			requests.entries[requests.count].issued = v
			requests.count += 1
			continue
		case a.RequestExpired:
			if requests==nil { return nil,0,.InvalidHistory }
			entry := find_request(requests,v.id)
			if entry==nil || entry.issued.reference!=v.issuance { return nil,0,.InvalidReference }
			if entry.expiry!=nil { return nil,0,.InvalidHistory }
			entry.expiry = v
			continue
		case a.TaskCreated:
			created := v
			key := Key{v.task,v.run}
			slot = len(states)+1
			_,p,exists := map_upsert(&by_key,key,slot)
			if p==nil { return nil,0,.ResourceLimit }
			input: [48]u8
			copy(input[:16],created.task[:])
			copy(input[16:32],created.run[:])
			copy(input[32:],created.command[:])
			if exists || !unique(&ids,.Command,cast([16]u8)v.command) || !unique(&ids,.Evidence,cast([16]u8)v.evidence) ||
			   v.input_digest!=hash("warband.task.v1\x00",input[:]) { return nil,0,.InvalidHistory }
			if _,err := append(&states,state.Evidence{task=v,task_version=1}); err!=nil { return nil,0,.ResourceLimit }
			if _,err := append(&dispositions,a.AttemptDisposition{}); err!=nil { return nil,0,.ResourceLimit }
		case a.ProposalRecorded: slot = by_key[Key{v.task,v.run}]
		case a.AuthorizationRecorded: slot = owners[v.proposal.sequence-1]
		case a.DispatchClaimed: slot = owners[v.authorization.sequence-1]
		case a.ObservationRecorded: slot = owners[v.claim.sequence-1]
		case a.EvaluationRecorded: slot = owners[v.observation.sequence-1]
		case a.TransitionAccepted: slot = owners[v.evaluation.sequence-1]
		case a.CapabilityRevoked: slot = owners[v.authorization.sequence-1]
		case a.AttemptDisposition: slot = owners[v.claim.sequence-1]
		case a.RejectionRecorded:
			if v.stage==7 && v.reason==13 && v.related==nil {
				if used>=len(receipts) || receipts[used].digest!=v.rejected_input_digest || receipts[used].epoch>v.reference.epoch { return nil,0,.InvalidHistory }
				used += 1
			}
			continue // optional Ref, when present, resolves by its verified scope and earlier position
		}
		if slot==0 { return nil,0,.InvalidReference }
		when markers {
			if root := marker.latest[slot]; root!=0 {
				if marker.chains[root].view.complete { return nil,0,.InvalidHistory }
				delete_key(&marker.latest,slot)
			}
		}
		owners[i] = slot
		h := &states[slot-1]
		#partial switch v in rec.event {
		case a.TaskCreated,a.RejectionRecorded:
		case a.ProposalRecorded:
			if h.proposal!=nil || h.transition!=nil || v.expected_task_version!=h.task_version ||
			   !unique(&ids,.Proposal,cast([16]u8)v.proposal) { return nil,0,.InvalidHistory }
			h.proposal = v
		case a.AuthorizationRecorded:
			prop,ok := h.proposal.(a.ProposalRecorded)
			if !ok || prop.reference!=v.proposal { return nil,0,.InvalidReference }
			if h.permit!=nil || v.expected_control_revision!=h.control_revision || !unique(&ids,.Evidence,cast([16]u8)v.evidence) { return nil,0,.InvalidHistory }
			if v.decision==.Permit {
				if prop.approval_required || !unique(&ids,.Capability,cast([16]u8)v.capability) { return nil,0,.InvalidHistory }
				h.control_revision += 1
			}
			h.permit = v
		case a.DispatchClaimed:
			auth,ok := h.permit.(a.AuthorizationRecorded)
			if !ok || auth.reference!=v.authorization { return nil,0,.InvalidReference }
			when markers {
				if v.expected_task_version!=h.task_version || v.expected_control_revision!=h.control_revision { return nil,0,.InvalidHistory }
			}
			if h.claim!=nil || h.revoked || !unique(&ids,.Attempt,cast([16]u8)v.attempt) { return nil,0,.InvalidHistory }
			h.claim = v
			if !state.bound_claim(h^,auth.proposal) { return nil,0,.InvalidHistory }
			h.control_revision += 1
		case a.ObservationRecorded:
			claim,ok := h.claim.(a.DispatchClaimed)
			if !ok || claim.reference!=v.claim { return nil,0,.InvalidReference }
			if h.observation!=nil || !unique(&ids,.Evidence,cast([16]u8)v.evidence) { return nil,0,.InvalidHistory }
			h.observation = v
			h.observation_digest = rec.digest
			h.observation_bytes,_ = a.encode_observation_recorded(v,v.reference.store,v.reference.epoch)
		case a.EvaluationRecorded:
			obs,ok := h.observation.(a.ObservationRecorded)
			if !ok || obs.reference!=v.observation || v.claim!=obs.claim { return nil,0,.InvalidReference }
			if h.evaluation!=nil || !unique(&ids,.Evidence,cast([16]u8)v.evidence) || v.observed_event_digest!=h.observation_digest ||
			   (v.verdict==.Verified)!=(obs.outcome==.Returned) { return nil,0,.InvalidHistory }
			h.evaluation = v
		case a.TransitionAccepted:
			eval,ok := h.evaluation.(a.EvaluationRecorded)
			if !ok || eval.reference!=v.evaluation || eval.claim!=v.claim { return nil,0,.InvalidReference }
			if state.decide(h^,v.evaluation,v.expected_task_version,v.expected_control_revision)!=.Eligible ||
			   !unique(&ids,.Transition,cast([16]u8)v.transition) { return nil,0,.InvalidHistory }
			h.transition = v
			h.task_version += 1
			h.control_revision += 1
		case a.CapabilityRevoked:
			auth,ok := h.permit.(a.AuthorizationRecorded)
			if !ok || auth.reference!=v.authorization { return nil,0,.InvalidReference }
			if auth.decision!=.Permit || auth.capability!=v.capability || h.revoked ||
			   v.expected_control_revision!=h.control_revision { return nil,0,.InvalidHistory }
			h.revoked = true
			h.control_revision += 1
		case a.AttemptDisposition:
			claim,ok := h.claim.(a.DispatchClaimed)
			if !ok || claim.reference!=v.claim { return nil,0,.InvalidReference }
			if h.terminal || h.transition!=nil || v.expected_control_revision!=h.control_revision { return nil,0,.InvalidHistory }
			h.terminal = true
			dispositions[slot-1] = v
			h.control_revision += 1
		}
	}
	result,err := make([]Projection,len(states),context.allocator)
	if err!=nil { return nil,0,.ResourceLimit }
	for h,i in states {
		task := h.task.(a.TaskCreated)
		p := &result[i]
		p.store,p.epoch = task.reference.store,task.reference.epoch
		p.key = {task.task,task.run}
		p.task_version,p.control_revision = h.task_version,h.control_revision
		p.complete,p.revoked = h.transition!=nil,h.revoked
		if auth,ok := h.permit.(a.AuthorizationRecorded); ok { p.authorization = u8(auth.decision) }
		if claim,ok := h.claim.(a.DispatchClaimed); ok { p.consumed=true; p.attempt=claim.attempt }
		if obs,ok := h.observation.(a.ObservationRecorded); ok { p.observation=u8(obs.outcome) }
		if ev,ok := h.evaluation.(a.EvaluationRecorded); ok { p.verdict=u8(ev.verdict) }
		when markers {
			if root := marker.latest[i+1]; root!=0 {
				view := marker.chains[root].view
				view.store,view.epoch,view.key = p.store,p.epoch,p.key
				view.task_version,view.control_revision = h.task_version,h.control_revision
				p^ = view
				continue
			}
		}
		if h.terminal { p.disposition,p.disposition_reason = u8(dispositions[i].disposition),dispositions[i].reason }
	}
	return result,used,.None
}
