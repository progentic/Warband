package reconcile

import s "../store"
import c "../custody"
import e "../domain/events"
import client "client"
import "core:crypto/sha2"
import "core:encoding/endian"

Archive :: struct {path: cstring, transition: []u8} // WBCR epoch-change request, ascending epoch order
Outcome :: enum {Ready, PendingConfirmation, ConfirmedResponsePending, PendingEventMissing, UnattestedTail, IntegrityFault,
                 StoreIdentityMismatch, EpochMismatch, CustodyUnavailable, LockUnavailable, StoreUnavailable, ReconciliationRequired, RecoveryLimitExceeded, AttestationUncertain}

@(private)
receipt :: proc(frame: c.RejectionFrameBytes) -> s.Import {
	frame := frame
	entry: s.Import
	entry.id.ordinal,_ = endian.get_u64(frame[11:19],.Little)
	copy(entry.id.hash[:],frame[len(frame)-32:])
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx,frame[:])
	sha2.final(&ctx,entry.digest[:])
	return entry
}

// The epoch request is untrusted input. Its derived new head must be the starting
// link of the next validated segment, all the way to the authenticated live head.
run :: proc(path: cstring,session: ^client.Session,archives: []Archive,retry: Maybe(s.ReceiptId), compared: ^e.EventRef) -> (result: Outcome) {
	defer if session.exhausted { result = .RecoveryLimitExceeded }
	start := client.wb_elapsed_ms()
	if start < 0 || u64(len(archives))+1 != u64(session.epoch) { return .EpochMismatch }
	session.deadline = start+60_000
	if !s.limit_sqlite() { return .StoreUnavailable }
	fd := client.wb_writer_gate(path)
	if fd < 0 { return .LockUnavailable }
	defer client.wb_release_gate(fd)
	locked := client.wb_elapsed_ms()
	if locked < start || locked-start >= 5_000 { return .LockUnavailable }
	writer, err := s.open_writer(path)
	if err != .None { return .StoreUnavailable }
	defer if !s.close_writer(&writer) { result = .StoreUnavailable }
	if !s.limit_writer_cache(writer) { return .StoreUnavailable }
	return reconcile_locked(writer,session,archives,retry,compared)
}

// Caller holds the store inode lock throughout reconciliation and the following gate.
reconcile_locked :: proc(writer: s.VerifiedWriter,session: ^client.Session,archives: []Archive,retry: Maybe(s.ReceiptId), compared: ^e.EventRef) -> (result: Outcome) {
	defer if session.exhausted { result = .RecoveryLimitExceeded }
	if u64(len(archives))+1 != u64(session.epoch) { return .EpochMismatch }
	page, ok := client.verify(session,0)
	if !ok { return .CustodyUnavailable }
	cp := page.committed
	if cp.store != session.store || cp.epoch != session.epoch { return .IntegrityFault }
	tip := page.tip
	imports: [dynamic]s.Import
	defer delete(imports)
	genesis: Maybe([32]u8)
	for archive,i in archives {
		if !client.within_budget(session,1) { return .RecoveryLimitExceeded }
		req, decode_err := c.decode_request(archive.transition,session.store,e.Epoch(i+1))
		if decode_err != .None || req.operation != .EpochChange { return .EpochMismatch }
		transition := req.payload.(c.EpochRequest)
		old := transition.old
		if !s.inspect_archive(archive.path,old,genesis,&imports,session) { return .IntegrityFault }
		head: [32]u8
		copy(head[:],archive.transition[91:123]) // verified WBCR header + EPOCH new_head
		genesis = head
	}
	seg, valid := s.inspect_writer(writer,cp,genesis,&imports,session)
	if !valid { return .IntegrityFault }
	initial_pending := page.pending
	pending, live := initial_pending.(e.Pledge)
	tail, ahead := seg.tail.(e.Pledge)
	p, t: ^e.Pledge
	if live { p = &pending }
	if ahead { t = &tail }
	outcome := Outcome.Ready
	switch e.classify_recovery(cp,seg.journal,p,t) {
	case .StoreIdentityMismatch: return .StoreIdentityMismatch
	case .EpochMismatch: return .EpochMismatch
	case .IntegrityFault: return .IntegrityFault
	case .PendingEventMissing: return .PendingEventMissing
	case .UnattestedTail: return .UnattestedTail
	case .PendingConfirmation: outcome = .PendingConfirmation
	case .Ready:
	}
	// Only after tail classification compare derived rows against the authenticated
	// earliest-receipt stream. Neither a watermark nor an index hit can skip proof.
	if !s.watermark_matches(writer,session.store,seg.last_import) { return .IntegrityFault }
	cursor: u64
	replayed: Maybe(e.EventRef)
	for entry in imports {
		frame, present := page.rejection.(c.RejectionFrameBytes)
		if !present { return .IntegrityFault }
		receipt_epoch,_ := endian.get_u64(frame[99:107],.Little)
		if receipt_epoch > u64(entry.ref.epoch) { return .IntegrityFault }
		observed := receipt(frame)
		if observed.id != entry.id || observed.digest != entry.digest || entry.id.ordinal > tip { return .IntegrityFault }
		if retry == entry.id { replayed = entry.ref }
		cursor = entry.id.ordinal
		page, ok = client.verify(session,cursor)
		if !ok || page.tip < tip || page.committed != cp || page.pending != initial_pending { return .IntegrityFault }
	}
	if retry != nil && replayed == nil { return .IntegrityFault }
	if outcome == .PendingConfirmation {
		if !s.confirm_stored(writer,session,pending,seg.tail_import,session.deadline) { return .AttestationUncertain }
		cp = seg.journal
	} else if replayed != nil { outcome = .ConfirmedResponsePending }
	local_mark := seg.last_import
	for {
		frame, present := page.rejection.(c.RejectionFrameBytes)
		if !present { break }
		entry := receipt(frame)
		if entry.id.ordinal > tip { break } // authenticated earliest receipt lies beyond the fixed interval
		receipt_epoch,_ := endian.get_u64(frame[99:107],.Little)
		if receipt_epoch > u64(cp.epoch) { return .IntegrityFault }
		if retry != nil { return .ReconciliationRequired }
		cp, ok = s.append_verified_event(writer,session,cp,local_mark,entry)
		if !ok { return .AttestationUncertain }
		local_mark = entry.id.ordinal
		page, ok = client.verify(session,local_mark)
		if !ok || page.tip < tip || page.committed != cp || page.pending != nil { return .IntegrityFault }
	}
	if !client.within_budget(session) { return .IntegrityFault }
	if ref, found := replayed.(e.EventRef); found { compared^ = ref }
	return outcome
}
