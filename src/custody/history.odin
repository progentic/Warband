package custody

import "../domain/events"
import "core:encoding/endian"

HistoryStatus :: enum {
	AttestationHistoryFault,
	Unsupported,
	HeadPublicationPending,
	TornFinalRecord,
	Consistent,
	Unenrolled,
	CheckpointInconsistent,
	MemoryLimitExceeded,
}

HistoryView :: struct {
	committed: HeadFile,
	pending: Maybe(events.Pledge),
	pending_record_hash: [32]u8,
	ordinal: u64,
	record_hash: [32]u8,
}

// Supply exact history bytes and an already decoded head, or nil if absent.
// Consistent may still carry a pending pledge requiring journal reconciliation.
validate_custody_history :: proc(history: []u8, published: Maybe(HeadFile), store: events.StoreId) -> (HistoryView, HistoryStatus) {
	empty_store := events.StoreId{}
	if store == empty_store {
		return {}, .AttestationHistoryFault
	}
	head, has_head := published.(HeadFile)
	authorizations: map[events.AuthorizationId]bool
	defer delete(authorizations)
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
		epoch := view.committed.checkpoint.epoch
		decode_epoch := epoch
		if epoch == 0 && len(bytes) > 6 && bytes[6] == u8(FrameKind.Genesis) {
			decode_epoch = 1
		}
		record, err := decode_record(bytes, store, decode_epoch, view.ordinal+1, view.record_hash)
		if err == .Truncated && (head_seen || (!has_head && epoch == 0)) {
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
			if epoch != 0 {
				return {}, .AttestationHistoryFault
			}
			genesis := record.payload.(Genesis)
			if map_insert(&authorizations, genesis.authorization, true) == nil {
				return {}, .MemoryLimitExceeded
			}
			genesis_hash, genesis_error := genesis_head(genesis, store)
			if genesis_error != .None {
				return {}, .AttestationHistoryFault
			}
			view.committed = {{store = store, epoch = 1, head = genesis_hash}, view.record_hash}
		case .Pending:
			pledge := record.payload.(events.Pledge)
			if view.pending != nil || events.classify_prepare(pledge, view.committed.checkpoint, nil) != .EligiblePledge {
				return {}, .AttestationHistoryFault
			}
			view.pending = pledge
			view.pending_record_hash = view.record_hash
		case .Committed:
			pledge := record.payload.(events.Pledge)
			pending, ok := view.pending.(events.Pledge)
			if !ok || pending != pledge {
				return {}, .AttestationHistoryFault
			}
			view.committed = {{store, epoch, pledge.sequence, pledge.head}, view.record_hash}
			view.pending = nil
			view.pending_record_hash = {}
		case .Epoch:
			change := record.payload.(EpochChange)
			if change.old != view.committed.checkpoint || change.unresolved_pending_record_hash != view.pending_record_hash {
				return {}, .AttestationHistoryFault
			}
			_, entry, duplicate := map_upsert(&authorizations, change.authorization, true)
			if entry == nil {
				return {}, .MemoryLimitExceeded
			}
			if duplicate {
				return {}, .AttestationHistoryFault
			}
			// decode_epoch already checked the successor epoch, zero sequence and new head.
			view.committed = {decoded_epoch_checkpoint(bytes[83:size-32], store), view.record_hash}
			view.pending = nil
			view.pending_record_hash = {}
		case .Rejection:
			// A denial advances only the custody ordinal and record hash.
		}
		view.ordinal = record.ordinal
		if has_head && view.committed.checkpoint.epoch != 0 && view.committed == head {
			head_seen = true
		}
		remaining = remaining[size:]
	}
	if !has_head {
		if view.committed.checkpoint.epoch == 0 {
			return view, .Unenrolled
		}
		return view, .CheckpointInconsistent
	}
	if !head_seen {
		return {}, .AttestationHistoryFault
	}
	if head != view.committed {
		return view, .HeadPublicationPending
	}
	return view, .Consistent
}
