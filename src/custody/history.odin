package custody

import "../domain/events"
import "core:encoding/endian"

HistoryStatus :: enum {
	AttestationHistoryFault,
	Unsupported,
	HeadPublicationPending,
	TornFinalRecord,
	Consistent,
}

HistoryView :: struct {
	committed: HeadFile,
	pending: Maybe(events.Pledge),
	ordinal: u64,
	record_hash: [32]u8,
}

// The caller supplies an already decoded published head and the exact history bytes.
// Consistent may still carry a pending pledge requiring journal reconciliation.
validate_custody_history :: proc(history: []u8, published: HeadFile, store: events.StoreId) -> (HistoryView, HistoryStatus) {
	if len(history) == 0 {
		// A supplied published head has no supporting genesis.
		return {}, .AttestationHistoryFault
	}
	view: HistoryView
	head_seen := false
	remaining := history
	for len(remaining) > 0 {
		size := len(remaining)
		if size >= 11 {
			payload_length, _ := endian.get_u32(remaining[7:11], .Little)
			size = int(min(u64(size), u64(FrameOverhead) + u64(payload_length)))
		}
		bytes := remaining[:size]
		record, err := decode_record(bytes, store, 1, view.ordinal+1, view.record_hash)
		if err == .Truncated && head_seen {
			return view, .TornFinalRecord
		}
		if err == .Unsupported {
			return {}, .Unsupported
		}
		if err != .None {
			return {}, .AttestationHistoryFault
		}
		copy(view.record_hash[:], bytes[size-32:])
		switch record.kind {
		case .Genesis:
			if view.ordinal != 0 {
				return {}, .AttestationHistoryFault
			}
			head, genesis_error := genesis_head(record.payload.(Genesis), store)
			if genesis_error != .None {
				return {}, .AttestationHistoryFault
			}
			view.committed = {{store = store, epoch = 1, head = head}, view.record_hash}
		case .Pending:
			pledge := record.payload.(events.Pledge)
			if view.pending != nil || events.classify_prepare(pledge, view.committed.checkpoint, nil) != .EligiblePledge {
				return {}, .AttestationHistoryFault
			}
			view.pending = pledge
		case .Committed:
			pledge := record.payload.(events.Pledge)
			pending, ok := view.pending.(events.Pledge)
			if !ok || pending != pledge {
				return {}, .AttestationHistoryFault
			}
			view.committed = {{store, 1, pledge.sequence, pledge.head}, view.record_hash}
			view.pending = nil
		case .Epoch, .Rejection:
			return {}, .Unsupported
		}
		view.ordinal = record.ordinal
		if view.committed == published {
			head_seen = true
		}
		remaining = remaining[size:]
	}
	if !head_seen {
		return {}, .AttestationHistoryFault
	}
	if published != view.committed {
		return view, .HeadPublicationPending
	}
	return view, .Consistent
}
