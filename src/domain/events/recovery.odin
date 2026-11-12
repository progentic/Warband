package events

RecoveryDecision :: enum {
	IntegrityFault,
	StoreIdentityMismatch,
	EpochMismatch,
	UnattestedTail,
	PendingEventMissing,
	PendingConfirmation,
	Ready,
}

// Callers validate custody/history and the checkpoint-covered prefix first.
// persisted is the journal's final event when ahead of committed, otherwise nil.
classify_recovery :: proc(committed, journal: Checkpoint, pending, persisted: ^Pledge) -> RecoveryDecision {
	empty_store := StoreId{}
	if committed.store == empty_store || journal.store != committed.store ||
	   (pending != nil && pending.store != committed.store) ||
	   (persisted != nil && persisted.store != committed.store) {
		return .StoreIdentityMismatch
	}
	if committed.epoch == 0 || journal.epoch != committed.epoch ||
	   (pending != nil && pending.epoch != committed.epoch) ||
	   (persisted != nil && persisted.epoch != committed.epoch) {
		return .EpochMismatch
	}
	if journal.sequence < committed.sequence {
		return .IntegrityFault
	}
	if pending != nil && classify_prepare(pending^, committed, nil) != .EligiblePledge {
		return .IntegrityFault
	}
	if journal.sequence == committed.sequence {
		if journal.head != committed.head || persisted != nil {
			return .IntegrityFault
		}
		if pending != nil {
			return .PendingEventMissing
		}
		return .Ready
	}
	if pending == nil || journal.sequence > pending.sequence {
		return .UnattestedTail
	}
	if persisted == nil || persisted^ != pending^ || journal.head != pending.head {
		return .IntegrityFault
	}
	return .PendingConfirmation
}
