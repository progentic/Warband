package store

import a "../audit"
import c "../custody"
import e "../domain/events"
import client "../runtime/client"
import "core:sys/linux"

TEST_STOP_SIGNAL :: linux.Signal.SIGSTOP
STOP_AFTER_COMMIT :: #config(WARBAND_TEST_STOP_AFTER_COMMIT, false)

confirm_stored :: proc(w: VerifiedWriter, s: ^client.Session, p: e.Pledge, expected: Maybe(Import), deadline: i64, marker := false) -> bool {
	if !client.within_budget(s,1) { return false }
	row, ok := event_row((cast(^WriterState)w).db, {p.store,p.epoch,p.sequence},marker=marker)
	if !ok || row.pledge != p || row.receipt != expected { return false }
	if row.acceptance != nil {
		checkpoint := e.Checkpoint{p.store,p.epoch,p.sequence,p.head}
		_, checked := acceptance_snapshot(w,checkpoint,s)
		if !checked { return false }
	}
	reply, confirmed := client.exchange(s,{.Confirm,p},deadline)
	head := e.Checkpoint{p.store,p.epoch,p.sequence,p.head}
	return confirmed && reply.committed == head && reply.pending == nil && reply.receipt != [32]u8{}
}

append_verified_event :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,prior: u64,entry: Import) -> (e.Checkpoint,bool) {
	start := client.wb_elapsed_ms()
	recorded := client.wb_recorded_us()
	if start < 0 || recorded < 0 || cp.sequence == max(e.Sequence) || entry.id.ordinal <= prior { return {},false }
	entry := entry
	entry.ref = {cp.store,cp.epoch,cp.sequence+1}
	value := a.RejectionRecorded{reference=entry.ref,recorded_time=u64(recorded),producer=5,stage=7,reason=13,
	                              rejected_input_digest=entry.digest,previous_head=cp.head}
	wire, err := a.encode_rejection_recorded(value,cp.store,cp.epoch)
	digest, hash_err := a.digest_rejection_recorded(value,cp.store,cp.epoch)
	if err != .None || hash_err != .None { return {},false }
	return append_pledged(w,s,cp,prior,entry,wire.data[:wire.length],digest,start,s.deadline)
}

@(private)
append_pledged :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,prior: u64,entry: Maybe(Import),bytes: []u8,digest: [32]u8,start,cutoff: i64, acceptance: ^AcceptanceCheck = nil, marker := false) -> (e.Checkpoint,bool) {
	if start < 0 || cp.sequence == max(e.Sequence) { return {},false }
	p := e.Pledge{store=cp.store,epoch=cp.epoch,previous_sequence=cp.sequence,previous_head=cp.head,sequence=cp.sequence+1,digest=digest}
	p.head = c.derive_head(p)
	deadline := min(start+30_000,s.deadline,cutoff)
	when #config(WARBAND_TEST_STOP_BEFORE_PREPARE, false) {
		if entry != nil && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return {},false }
	}
	reply, prepared := client.exchange(s,{.Prepare,p},deadline)
	if !prepared || reply.committed != cp || reply.pending != p || reply.receipt == ([32]u8{}) { return {},false }
	when #config(WARBAND_TEST_STOP_AFTER_PREPARE, false) {
		if entry != nil && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return {},false }
	}
	when #config(WARBAND_INTAKE_STOP, 0)==1 {
		if marker && linux.kill(linux.getpid(),TEST_STOP_SIGNAL)!=.NONE { return {},false }
	}
	now := client.wb_elapsed_ms()
	if now < start || now >= deadline || !client.within_budget(s,u64(cp.sequence)+1) || !commit_event(w,cp,prior,entry,bytes,acceptance) { return {},false }
	when STOP_AFTER_COMMIT {
		if entry != nil && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return {},false }
	}
	when #config(WARBAND_INTAKE_STOP, 0)==2 || #config(WARBAND_INTAKE_STOP, 0)==4 {
		target := marker if #config(WARBAND_INTAKE_STOP, 0)==2 else bytes[6]==1
		if target && linux.kill(linux.getpid(),TEST_STOP_SIGNAL)!=.NONE { return {},false }
	}
	mark := prior
	if imported, present := entry.(Import); present { mark = imported.id.ordinal }
	if !watermark_matches(w,cp.store,mark) || !confirm_stored(w,s,p,entry,deadline,marker) { return {},false }
	return {p.store,p.epoch,p.sequence,p.head},true
}

// The coordinator supplies only event types qualified for this isolated path.
NoopEvent :: union {a.AuthorizationRecorded, a.DispatchClaimed, a.RejectionRecorded, a.ObservationRecorded, a.EvaluationRecorded}
append_noop :: proc(w: VerifiedWriter, session: ^client.Session, cp: e.Checkpoint, mark: u64, event: NoopEvent, cutoff: i64) -> (e.Checkpoint,bool) {
	start := client.wb_elapsed_ms()
	next := e.EventRef{cp.store,cp.epoch,cp.sequence+1}
	switch v in event {
	case a.AuthorizationRecorded:
		if v.reference != next || v.previous_head != cp.head || v.decision != .Permit { return {},false }
		b, err := a.encode_authorization_recorded(v,cp.store,cp.epoch)
		d, de := a.digest_authorization_recorded(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b[:],d,start,cutoff)
	case a.DispatchClaimed:
		if v.reference != next || v.previous_head != cp.head { return {},false }
		b, err := a.encode_dispatch_claimed(v,cp.store,cp.epoch)
		d, de := a.digest_dispatch_claimed(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b[:],d,start,cutoff)
	case a.ObservationRecorded:
		if v.reference != next || v.previous_head != cp.head { return {},false }
		h, ok := noop_history(w,cp,session)
		claim, claimed := h.claim.(a.DispatchClaimed)
		if !ok || !claimed || claim.reference != v.claim || h.observation != nil || !available_evidence(h,v.evidence) { return {},false }
		b, err := a.encode_observation_recorded(v,cp.store,cp.epoch)
		d, de := a.digest_observation_recorded(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b[:],d,start,cutoff)
	case a.EvaluationRecorded:
		if v.reference != next || v.previous_head != cp.head { return {},false }
		h, ok := noop_history(w,cp,session)
		obs, found := h.observation.(a.ObservationRecorded)
		if !ok || !found || obs.reference != v.observation || obs.claim != v.claim || v.observed_event_digest != h.observation_digest ||
		   h.evaluation != nil || !available_evidence(h,v.evidence) { return {},false }
		b, err := a.encode_evaluation_recorded(v,cp.store,cp.epoch)
		d, de := a.digest_evaluation_recorded(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b[:],d,start,cutoff)
	case a.RejectionRecorded:
		if v.reference != next || v.previous_head != cp.head || v.producer != 2 || v.stage != 3 || (v.reason != 9 && v.reason != 5) || v.related == nil { return {},false }
		b, err := a.encode_rejection_recorded(v,cp.store,cp.epoch)
		d, de := a.digest_rejection_recorded(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b.data[:b.length],d,start,cutoff)
	}
	return {},false
}

// Only the live marker intake opts into kind-11 read-back. All v1 callers keep their reader.
append_intake :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,mark: u64,
                      event: union {a.TaskCreated,a.MarkerProposal}, deadline: i64) -> (e.Checkpoint,bool) {
	start := client.wb_elapsed_ms()
	if start<0 || cp.sequence==max(e.Sequence) { return {},false }
	next := e.EventRef{cp.store,cp.epoch,cp.sequence+1}
	switch v in event {
	case a.TaskCreated:
		if v.reference!=next || v.previous_head!=cp.head { return {},false }
		wire,err := a.encode_task_created(v,cp.store,cp.epoch)
		digest,de := a.digest_task_created(v,cp.store,cp.epoch)
		if err!=.None || de!=.None { return {},false }
		return append_pledged(w,s,cp,mark,nil,wire[:],digest,start,deadline)
	case a.MarkerProposal:
		if v.reference!=next || v.previous_head!=cp.head { return {},false }
		wire,err := a.encode_marker_proposal(v,cp.store,cp.epoch)
		digest,de := a.digest_marker_proposal(v,cp.store,cp.epoch)
		if err!=.None || de!=.None { return {},false }
		return append_pledged(w,s,cp,mark,nil,wire.data[:wire.length],digest,start,deadline,marker=true)
	}
	return {},false
}
