package events

StoreId :: distinct [16]u8
Epoch :: distinct u64
Sequence :: distinct u64
TaskId :: distinct [16]u8
RunId :: distinct [16]u8
CommandId :: distinct [16]u8
EvidenceId :: distinct [16]u8

EventRef :: struct {
	store: StoreId,
	epoch: Epoch,
	sequence: Sequence,
}

Error :: enum {
	None,
	EmptyStore,
	EmptyEpoch,
	EmptySequence,
	WrongStore,
	WrongEpoch,
	SequenceOverflow,
	EpochOverflow,
}

validate_event_ref :: proc(value: EventRef, store: StoreId, epoch: Epoch) -> Error {
	empty_store := StoreId{}
	if value.store == empty_store {
		return .EmptyStore
	}
	if value.epoch == 0 {
		return .EmptyEpoch
	}
	if value.sequence == 0 {
		return .EmptySequence
	}
	if value.store != store {
		return .WrongStore
	}
	if value.epoch != epoch {
		return .WrongEpoch
	}
	return .None
}

next_sequence :: proc(current: Sequence) -> (Sequence, Error) {
	if current == max(Sequence) {
		return 0, .SequenceOverflow
	}
	return current + 1, .None
}

next_epoch :: proc(current: Epoch) -> (Epoch, Error) {
	if current == 0 {
		return 0, .EmptyEpoch
	}
	if current == max(Epoch) {
		return 0, .EpochOverflow
	}
	return current + 1, .None
}
