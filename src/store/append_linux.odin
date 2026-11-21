package store

import a "../audit"
import c "../custody"
import e "../domain/events"
import client "../runtime/client"
import "core:sys/linux"

TEST_STOP_SIGNAL :: linux.Signal.SIGSTOP
STOP_AFTER_COMMIT :: #config(WARBAND_TEST_STOP_AFTER_COMMIT, false)

confirm_stored :: proc(w: VerifiedWriter, s: ^client.Session, p: e.Pledge, expected: Maybe(Import), deadline: i64) -> bool {
	if !client.within_budget(s,1) { return false }
	row, ok := event_row((cast(^WriterState)w).db, {p.store,p.epoch,p.sequence})
	if !ok || row.pledge != p || row.receipt != expected { return false }
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
append_pledged :: proc(w: VerifiedWriter,s: ^client.Session,cp: e.Checkpoint,prior: u64,entry: Maybe(Import),bytes: []u8,digest: [32]u8,start,cutoff: i64) -> (e.Checkpoint,bool) {
	if start < 0 || cp.sequence == max(e.Sequence) { return {},false }
	p := e.Pledge{store=cp.store,epoch=cp.epoch,previous_sequence=cp.sequence,previous_head=cp.head,sequence=cp.sequence+1,digest=digest}
	p.head = c.derive_head(p)
	deadline := min(start+30_000,s.deadline,cutoff)
	reply, prepared := client.exchange(s,{.Prepare,p},deadline)
	if !prepared || reply.committed != cp || reply.pending != p || reply.receipt == ([32]u8{}) { return {},false }
	now := client.wb_elapsed_ms()
	if now < start || now >= deadline || !client.within_budget(s,u64(cp.sequence)+1) || !commit_event(w,cp,prior,entry,bytes) { return {},false }
	when STOP_AFTER_COMMIT {
		if entry != nil && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { return {},false }
	}
	mark := prior
	if imported, present := entry.(Import); present { mark = imported.id.ordinal }
	if !watermark_matches(w,cp.store,mark) || !confirm_stored(w,s,p,entry,deadline) { return {},false }
	return {p.store,p.epoch,p.sequence,p.head},true
}

// The live gate supplies a typed event. Only the three qualified shapes reach SQLite.
NoopEvent :: union {a.AuthorizationRecorded, a.DispatchClaimed, a.RejectionRecorded}
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
	case a.RejectionRecorded:
		if v.reference != next || v.previous_head != cp.head || v.producer != 2 || v.stage != 3 || (v.reason != 9 && v.reason != 5) || v.related == nil { return {},false }
		b, err := a.encode_rejection_recorded(v,cp.store,cp.epoch)
		d, de := a.digest_rejection_recorded(v,cp.store,cp.epoch)
		if err != .None || de != .None { return {},false }
		return append_pledged(w,session,cp,mark,nil,b.data[:b.length],d,start,cutoff)
	}
	return {},false
}
