package events

ConfirmDecision :: enum {
	InvalidIdentity,
	MissingPledge,
	RequestMismatch,
	HeadPublicationPending,
	EligibleConfirmation,
	CommittedReplay,
}

// current is the validated committed checkpoint, even before head publication.
// latest_committed supplies its full tuple; publication is a supplied observation.
classify_confirm :: proc(request: Pledge, current: Checkpoint, pending, latest_committed: ^Pledge, head_published: bool) -> ConfirmDecision {
	reference := EventRef{store = request.store, epoch = request.epoch, sequence = request.sequence}
	if validate_event_ref(reference, current.store, current.epoch) != .None {
		return .InvalidIdentity
	}
	if latest_committed != nil && request == latest_committed^ {
		if request.sequence != current.sequence || request.head != current.head {
			return .RequestMismatch
		}
		if !head_published {
			return .HeadPublicationPending
		}
		return .CommittedReplay
	}
	if pending == nil {
		return .MissingPledge
	}
	if classify_prepare(request, current, pending) != .PendingReplay {
		return .RequestMismatch
	}
	if !head_published {
		return .HeadPublicationPending
	}
	return .EligibleConfirmation
}
