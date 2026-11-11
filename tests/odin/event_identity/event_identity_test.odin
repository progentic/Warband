package event_identity_test

import "core:testing"
import "../../../src/domain/events"

#assert(events.Epoch != events.Sequence)

@(test)
event_reference_checks_identity_and_scope :: proc(t: ^testing.T) {
	store := events.StoreId{}
	store[0] = 1
	value := events.EventRef{store = store, epoch = 1, sequence = 1}
	testing.expect_value(t, events.validate_event_ref(value, store, 1), .None)
	other_store := store
	other_store[0] = 2
	testing.expect_value(t, events.validate_event_ref(value, other_store, 1), .WrongStore)
	testing.expect_value(t, events.validate_event_ref(value, store, 2), .WrongEpoch)
	invalid := value
	invalid.store = events.StoreId{}
	testing.expect_value(t, events.validate_event_ref(invalid, store, 1), .EmptyStore)
	invalid = value
	invalid.epoch = 0
	testing.expect_value(t, events.validate_event_ref(invalid, store, 1), .EmptyEpoch)
	invalid = value
	invalid.sequence = 0
	testing.expect_value(t, events.validate_event_ref(invalid, store, 1), .EmptySequence)
}

@(test)
sequence_advance_rejects_overflow :: proc(t: ^testing.T) {
	next, err := events.next_sequence(0)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, next, events.Sequence(1))
	_, err = events.next_sequence(max(events.Sequence))
	testing.expect_value(t, err, .SequenceOverflow)
}

@(test)
epoch_advance_rejects_zero_and_overflow :: proc(t: ^testing.T) {
	next, err := events.next_epoch(1)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, next, events.Epoch(2))
	_, err = events.next_epoch(0)
	testing.expect_value(t, err, .EmptyEpoch)
	_, err = events.next_epoch(max(events.Epoch))
	testing.expect_value(t, err, .EpochOverflow)
}

@(test)
prepare_classification_checks_binding_and_pending_replay :: proc(t: ^testing.T) {
	store := events.StoreId{}
	store[0] = 1
	checkpoint := events.Checkpoint{store = store, epoch = 1}
	checkpoint.head[0] = 1
	request := events.Pledge{store = store, epoch = 1, previous_head = checkpoint.head, sequence = 1}
	request.head[0] = 2
	request.digest[0] = 3
	testing.expect_value(t, events.classify_prepare(request, checkpoint, nil), .EligiblePledge)
	testing.expect_value(t, events.classify_prepare(request, checkpoint, &request), .PendingReplay)
	changed := request
	changed.head[0] = 4
	testing.expect_value(t, events.classify_prepare(changed, checkpoint, &request), .PendingConflict)
	changed = request
	changed.epoch = 2
	testing.expect_value(t, events.classify_prepare(changed, checkpoint, nil), .InvalidIdentity)
	changed = request
	changed.previous_head[0] = 4
	testing.expect_value(t, events.classify_prepare(changed, checkpoint, nil), .InvalidPredecessor)
	changed = request
	changed.sequence = 2
	testing.expect_value(t, events.classify_prepare(changed, checkpoint, nil), .InvalidSequence)
}

@(test)
confirm_classification_checks_pending_and_committed_replay :: proc(t: ^testing.T) {
	store := events.StoreId{}
	store[0] = 1
	checkpoint := events.Checkpoint{store = store, epoch = 1}
	request := events.Pledge{store = store, epoch = 1, sequence = 1}
	request.head[0] = 2
	request.digest[0] = 3
	testing.expect_value(t, events.classify_confirm(request, checkpoint, &request, nil, true), .EligibleConfirmation)
	testing.expect_value(t, events.classify_confirm(request, checkpoint, nil, nil, true), .MissingPledge)
	testing.expect_value(t, events.classify_confirm(request, checkpoint, &request, nil, false), .HeadPublicationPending)
	changed := request
	changed.digest[0] = 4
	testing.expect_value(t, events.classify_confirm(changed, checkpoint, &request, nil, true), .RequestMismatch)
	changed = request
	changed.epoch = 2
	testing.expect_value(t, events.classify_confirm(changed, checkpoint, &request, nil, true), .InvalidIdentity)
	changed = request
	changed.previous_head[0] = 5
	testing.expect_value(t, events.classify_confirm(changed, checkpoint, &changed, nil, true), .RequestMismatch)
	checkpoint.sequence = request.sequence
	checkpoint.head = request.head
	later := events.Pledge{store = store, epoch = 1, previous_sequence = 1, previous_head = request.head, sequence = 2}
	later.head[0] = 6
	later_before := later
	testing.expect_value(t, events.classify_confirm(request, checkpoint, &later, &request, true), .CommittedReplay)
	testing.expect_value(t, later, later_before)
	testing.expect_value(t, events.classify_confirm(request, checkpoint, &later, &request, false), .HeadPublicationPending)
	changed = request
	changed.digest[0] = 4
	testing.expect_value(t, events.classify_confirm(changed, checkpoint, &later, &request, true), .RequestMismatch)
	checkpoint.head[0] = 7
	testing.expect_value(t, events.classify_confirm(request, checkpoint, &later, &request, true), .RequestMismatch)
}
