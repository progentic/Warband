package custody_test

import "core:testing"
import "../../../src/domain/events"
import "../../../src/custody"

@(test)
history_checks_enrolled_prefix_pledge_and_published_head :: proc(t: ^testing.T) {
	genesis := genesis_value()
	store := genesis.store
	pledge := golden_pledge(golden_bytes())
	gen, gen_error := custody.encode_record({kind = .Genesis, ordinal = 1, payload = genesis}, store, 1)
	testing.expect_value(t, gen_error, .None)
	gen_head := custody.HeadFile{checkpoint = {store = store, epoch = 1, head = pledge.previous_head}}
	copy(gen_head.committed_record_hash[:], gen.data[gen.length-32:gen.length])
	pending, pending_error := custody.encode_record({kind = .Pending, ordinal = 2, previous_record_hash = gen_head.committed_record_hash, payload = pledge}, store, 1)
	testing.expect_value(t, pending_error, .None)
	pending_hash: [32]u8
	copy(pending_hash[:], pending.data[pending.length-32:pending.length])
	commit := custody.CustodyRecord{kind = .Committed, ordinal = 3, previous_record_hash = pending_hash, payload = pledge}
	committed, commit_error := custody.encode_record(commit, store, 1)
	testing.expect_value(t, commit_error, .None)
	tip := custody.HeadFile{checkpoint = {store, 1, pledge.sequence, pledge.head}}
	expected := literal_bytes("cf70871bc3142a9c387b900193db9c44a33894c5f1b5fcbfe065adca3530fc46")
	defer delete(expected)
	copy(tip.committed_record_hash[:], expected)
	history: [2048]u8
	copy(history[:], gen.data[:gen.length])
	copy(history[gen.length:], pending.data[:pending.length])
	start := gen.length + pending.length
	end := start + committed.length
	copy(history[start:], committed.data[:committed.length])
	view, status := custody.validate_custody_history(history[:end], tip, store)
	testing.expect_value(t, status, .Consistent)
	testing.expect_value(t, view.committed, tip)
	testing.expect_value(t, view.ordinal, u64(3))
	testing.expect(t, view.pending == nil)
	view, status = custody.validate_custody_history(history[:start], gen_head, store)
	testing.expect_value(t, status, .Consistent)
	live, ok := view.pending.(type_of(pledge))
	testing.expect(t, ok)
	testing.expect_value(t, live, pledge)
	_, status = custody.validate_custody_history(history[:end], gen_head, store)
	testing.expect_value(t, status, .HeadPublicationPending)
	_, status = custody.validate_custody_history(history[:end-1], gen_head, store)
	testing.expect_value(t, status, .TornFinalRecord)
	_, status = custody.validate_custody_history(history[:end-1], tip, store)
	testing.expect_value(t, status, .AttestationHistoryFault)
	wrong_head := tip
	wrong_head.committed_record_hash = pending_hash
	_, status = custody.validate_custody_history(history[:end], wrong_head, store)
	testing.expect_value(t, status, .AttestationHistoryFault)

	// Re-encode valid checksums so each failure isolates a history rule.
	commit.previous_record_hash = gen_head.committed_record_hash
	conflict, err := custody.encode_record(commit, store, 1)
	testing.expect_value(t, err, .None)
	copy(history[start:], conflict.data[:conflict.length])
	_, status = custody.validate_custody_history(history[:end], gen_head, store)
	testing.expect_value(t, status, .AttestationHistoryFault)
	commit.previous_record_hash = pending_hash
	pledge.digest[0] ~= 1
	pledge.head = custody.derive_head(pledge)
	commit.payload = pledge
	conflict, err = custody.encode_record(commit, store, 1)
	testing.expect_value(t, err, .None)
	copy(history[start:], conflict.data[:conflict.length])
	_, status = custody.validate_custody_history(history[:end], gen_head, store)
	testing.expect_value(t, status, .AttestationHistoryFault)
}

HistoryExample :: struct {
	bytes: [4096]u8,
	length: int,
	ordinal: u64,
	hash: [32]u8,
}

@(private)
append_example :: proc(t: ^testing.T, history: ^HistoryExample, kind: custody.FrameKind, payload: custody.FramePayload, epoch: events.Epoch) {
	record := custody.CustodyRecord{kind, history.ordinal+1, history.hash, payload}
	encoded, err := custody.encode_record(record, genesis_value().store, epoch)
	testing.expect_value(t, err, .None)
	copy(history.bytes[history.length:][:encoded.length], encoded.data[:encoded.length])
	history.length += encoded.length
	history.ordinal += 1
	copy(history.hash[:], encoded.data[encoded.length-32:encoded.length])
}

@(test)
history_preserves_denials_and_checks_epoch_authorizations :: proc(t: ^testing.T) {
	genesis := genesis_value()
	store := genesis.store
	denial := custody.Rejection{store = store, fault_code = 15}
	h: HistoryExample
	append_example(t, &h, .Rejection, denial, 0)
	view, status := custody.validate_custody_history(h.bytes[:h.length], nil, store)
	testing.expect_value(t, status, .Unenrolled)
	testing.expect_value(t, view.ordinal, u64(1))
	testing.expect_value(t, view.record_hash, h.hash)
	testing.expect_value(t, view.committed, custody.HeadFile{})
	append_example(t, &h, .Genesis, genesis, 1)
	pledge := golden_pledge(golden_bytes())
	old := custody.HeadFile{checkpoint = {store, 1, 0, pledge.previous_head}, committed_record_hash = h.hash}
	_, status = custody.validate_custody_history(h.bytes[:h.length], nil, store)
	testing.expect_value(t, status, .CheckpointInconsistent)
	second_genesis := h
	append_example(t, &second_genesis, .Genesis, genesis, 1)
	_, status = custody.validate_custody_history(second_genesis.bytes[:second_genesis.length], old, store)
	testing.expect_value(t, status, .AttestationHistoryFault)
	wrong_epoch := h
	append_example(t, &wrong_epoch, .Rejection, denial, 0)
	_, status = custody.validate_custody_history(wrong_epoch.bytes[:wrong_epoch.length], old, store)
	testing.expect_value(t, status, .AttestationHistoryFault)

	append_example(t, &h, .Pending, pledge, 1)
	pending_hash := h.hash
	denial.epoch = 1
	append_example(t, &h, .Rejection, denial, 1)
	view, status = custody.validate_custody_history(h.bytes[:h.length], old, store)
	testing.expect_value(t, status, .Consistent)
	testing.expect_value(t, view.pending_record_hash, pending_hash)
	testing.expect_value(t, view.committed, old)
	epoch := epoch_value()
	epoch.old = old.checkpoint
	epoch.unresolved_pending_record_hash = pending_hash
	faults := [3]custody.EpochChange{epoch, epoch, epoch}
	faults[0].old.head[0] ~= 1
	faults[1].unresolved_pending_record_hash = h.hash
	faults[2].authorization = genesis.authorization
	for fault in faults {
		bad := h
		append_example(t, &bad, .Epoch, fault, 1)
		_, status = custody.validate_custody_history(bad.bytes[:bad.length], old, store)
		testing.expect_value(t, status, .AttestationHistoryFault)
	}

	append_example(t, &h, .Epoch, epoch, 1)
	encoded, err := custody.encode_epoch(epoch, store, 1)
	testing.expect_value(t, err, .None)
	next := custody.HeadFile{checkpoint = {store = store, epoch = 2}, committed_record_hash = h.hash}
	copy(next.checkpoint.head[:], encoded.data[80:112])
	view, status = custody.validate_custody_history(h.bytes[:h.length], old, store)
	testing.expect_value(t, status, .HeadPublicationPending)
	testing.expect_value(t, view.committed, next)
	testing.expect(t, view.pending == nil)
	pledge.epoch = 2
	pledge.previous_head = next.checkpoint.head
	pledge.head = custody.derive_head(pledge)
	append_example(t, &h, .Pending, pledge, 2)
	append_example(t, &h, .Committed, pledge, 2)
	final_head := custody.HeadFile{checkpoint = {store, 2, 1, pledge.head}, committed_record_hash = h.hash}
	view, status = custody.validate_custody_history(h.bytes[:h.length], final_head, store)
	testing.expect_value(t, status, .Consistent)
	testing.expect_value(t, view.ordinal, u64(7))
	testing.expect_value(t, view.committed, final_head)

	// A second epoch frame with a valid old head and no live pledge still needs a fresh ID.
	epoch.old = final_head.checkpoint
	epoch.unresolved_pending_record_hash = {}
	duplicate_id := h
	append_example(t, &duplicate_id, .Epoch, epoch, 2)
	_, status = custody.validate_custody_history(duplicate_id.bytes[:duplicate_id.length], final_head, store)
	testing.expect_value(t, status, .AttestationHistoryFault)
	epoch.authorization[0] ~= 1
	append_example(t, &h, .Epoch, epoch, 2)
	view, status = custody.validate_custody_history(h.bytes[:h.length], final_head, store)
	testing.expect_value(t, status, .HeadPublicationPending)
	testing.expect_value(t, view.committed.checkpoint.epoch, events.Epoch(3))
}
