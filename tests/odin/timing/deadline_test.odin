package timing_test

import "core:testing"
import t "../../../src/domain/timing"

@(test)
deadline_boundaries_are_strict :: proc(test: ^testing.T) {
	cases := [?]struct {stage: t.Stage, ms: u64, expired: t.Outcome} {
		{.Task, 180_000, .TaskDeadlineExceeded}, {.Operation, 30_000, .OperationDeadlineExceeded},
		{.LockWait, 5_000, .LockWaitExceeded}, {.Capability, 90_000, .ExpiredCapability},
	}
	starts := t.Starts{.Task=0, .Operation=0, .LockWait=0, .Capability=0}
	for c in cases {
		testing.expect_value(test, t.check(c.stage, starts, 0, c.ms-1), t.Decision{.WithinDeadline, 1})
		testing.expect_value(test, t.check(c.stage, starts, 0, c.ms), t.Decision{c.expired, 0})
		testing.expect_value(test, t.check(c.stage, starts, 0, c.ms+1), t.Decision{c.expired, 0})
	}
}

@(test)
invalid_observations_withhold_time :: proc(test: ^testing.T) {
	starts := t.Starts{.Task=1, .Operation=2, .LockWait=3, .Capability=nil}
	invalid := t.Decision{.InvalidObservation, 0}
	testing.expect_value(test, t.check(.LockWait, starts, nil, 5), invalid)
	testing.expect_value(test, t.check(.LockWait, starts, 5, nil), invalid)
	testing.expect_value(test, t.check(.LockWait, starts, 5, 4), invalid)
	testing.expect_value(test, t.check(.LockWait, starts, 2, 5), invalid)
	testing.expect_value(test, t.check(.Capability, starts, 5, 6), invalid)
	starts[.LockWait] = 1
	testing.expect_value(test, t.check(.LockWait, starts, 5, 6), invalid)
	starts[.Operation] = nil
	testing.expect_value(test, t.check(.LockWait, starts, 3, 180_001), invalid)
}

@(test)
retry_inherits_task_and_operation_time :: proc(test: ^testing.T) {
	starts := t.Starts{.Task=0, .Operation=175_000, .LockWait=175_000, .Capability=nil}
	testing.expect_value(test, t.check(.Operation, starts, 175_000, 175_000), t.Decision{.WithinDeadline, 5_000})
	testing.expect_value(test, t.check(.LockWait, starts, 175_000, 179_000), t.Decision{.WithinDeadline, 1_000})
	starts[.LockWait] = 179_000
	testing.expect_value(test, t.check(.LockWait, starts, 179_000, 180_000), t.Decision{.TaskDeadlineExceeded, 0})

	starts = {.Task=0, .Operation=10_000, .LockWait=39_000, .Capability=nil}
	testing.expect_value(test, t.check(.LockWait, starts, 39_000, 40_000), t.Decision{.OperationDeadlineExceeded, 0})
}

@(test)
dispatch_rechecks_capability_after_claim :: proc(test: ^testing.T) {
	origin := max(u64) - 90_000
	starts := t.Starts{.Task=origin, .Operation=nil, .LockWait=nil, .Capability=origin}
	claim := t.check(.Capability, starts, origin, max(u64)-1)
	testing.expect_value(test, claim, t.Decision{.WithinDeadline, 1})
	dispatch := t.check(.Capability, starts, max(u64)-1, max(u64))
	testing.expect_value(test, dispatch, t.Decision{.ExpiredCapability, 0})
}
