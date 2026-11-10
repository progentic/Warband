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
