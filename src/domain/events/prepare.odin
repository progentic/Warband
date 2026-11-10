package events

Pledge :: struct {
	store: StoreId,
	epoch: Epoch,
	previous_sequence: Sequence,
	previous_head: [32]u8,
	sequence: Sequence,
	head: [32]u8,
	digest: [32]u8,
}

Checkpoint :: struct {
	store: StoreId,
	epoch: Epoch,
	sequence: Sequence,
	head: [32]u8,
}

PrepareDecision :: enum {
	InvalidIdentity,
	InvalidSequence,
	InvalidPredecessor,
	PendingConflict,
	EligiblePledge,
	PendingReplay,
}

classify_prepare :: proc(request: Pledge, current: Checkpoint, pending: ^Pledge) -> PrepareDecision {
	empty_store := StoreId{}
	if request.store == empty_store || request.store != current.store || request.epoch == 0 || request.epoch != current.epoch || request.sequence == 0 {
		return .InvalidIdentity
	}
	if current.sequence == max(Sequence) {
		return .InvalidSequence
	}
	if request.sequence != current.sequence + 1 {
		return .InvalidSequence
	}
	if request.previous_sequence != current.sequence || request.previous_head != current.head {
		return .InvalidPredecessor
	}
	if pending != nil {
		if request == pending^ {
			return .PendingReplay
		}
		return .PendingConflict
	}
	return .EligiblePledge
}
