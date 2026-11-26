package timing

Stage :: enum {Task, Operation, LockWait, Capability}
Outcome :: enum {
	InvalidObservation,
	WithinDeadline,
	TaskDeadlineExceeded,
	OperationDeadlineExceeded,
	LockWaitExceeded,
	ExpiredCapability,
}

Decision :: struct {
	outcome: Outcome,
	remaining_ms: u64,
}

// Original elapsed-clock observations in milliseconds. Keep Task and Operation
// across exact retries; a later lock wait may have its own start.
Starts :: [Stage]Maybe(u64)

// previous_ms is the most recent successful observation, including stage starts.
// For capability timing, call at claim confirmation and again before dispatch.
check :: proc(stage: Stage, starts: Starts, previous_ms, now_ms: Maybe(u64)) -> Decision {
	previous, have_previous := previous_ms.(u64)
	now, have_now := now_ms.(u64)
	if !have_previous || !have_now || now < previous { return {} }

	required: bit_set[Stage] = {.Task}
	switch stage {
	case .Task:
	case .Operation: required += {.Operation}
	case .LockWait: required += {.Operation, .LockWait}
	case .Capability: required += {.Capability}
	case: return {}
	}

	limits := [Stage]struct {ms: u64, expired: Outcome} {
		.Task       = {180_000, .TaskDeadlineExceeded},
		.Operation  = { 30_000, .OperationDeadlineExceeded},
		.LockWait   = {  5_000, .LockWaitExceeded},
		.Capability = { 90_000, .ExpiredCapability},
	}
	decision := Decision{.WithinDeadline, max(u64)}
	earliest: u64
	for level in Stage {
		if level not_in required { continue }
		start, present := starts[level].(u64)
		if !present || start < earliest || start > previous { return {} }
		earliest = start
		limit := limits[level]
		elapsed := now - start
		if elapsed >= limit.ms {
			// Keep the outermost expired deadline, but validate every required input.
			if decision.outcome == .WithinDeadline { decision = {limit.expired, 0} }
		} else {
			decision.remaining_ms = min(decision.remaining_ms, limit.ms - elapsed)
		}
	}
	return decision
}
