package custody_test

import "core:testing"
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
