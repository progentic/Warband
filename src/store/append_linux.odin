package store

import a "../audit"
import c "../custody"
import e "../domain/events"
import client "../runtime/client"

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
	p := e.Pledge{store=cp.store,epoch=cp.epoch,previous_sequence=cp.sequence,previous_head=cp.head,sequence=entry.ref.sequence,digest=digest}
	p.head = c.derive_head(p)
	deadline := min(start+30_000,s.deadline)
	reply, prepared := client.exchange(s,{.Prepare,p},deadline)
	if !prepared || reply.committed != cp || reply.pending != p || reply.receipt == ([32]u8{}) { return {},false }
	now := client.wb_elapsed_ms()
	if now < start || now >= deadline || !client.within_budget(s,u64(cp.sequence)+1) || !commit_import(w,cp,prior,entry,wire.data[:wire.length]) { return {},false }
	if !watermark_matches(w,cp.store,entry.id.ordinal) || !confirm_stored(w,s,p,entry,deadline) { return {},false }
	return {p.store,p.epoch,p.sequence,p.head},true
}
