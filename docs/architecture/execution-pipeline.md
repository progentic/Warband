# Execution Pipeline

This document defines the normal path from user intent to verified state.

1. Warband records the task intent.
2. Warband builds a redacted, read-only state projection.
3. The proposal engine returns a typed proposal.
4. The gateway validates and normalizes the proposal.
5. Policy decides whether the proposal is rejected, permitted, or requires approval.
6. Warband issues a narrow, temporary capability.
7. The executor runs the action inside the allowed boundary.
8. Warband captures raw observations such as exit codes, file hashes, or API responses.
9. Independent evaluators compare the observations with the expected effect.
10. The state-transition boundary commits verified facts or rejects the transition.
11. The audit log records the full sequence.
12. Warband returns the verified result to the user.

A failure at any gate must stop or safely redirect the workflow. A later step must never silently bypass an earlier failed gate.

## Implementation status

This execution pipeline remains deferred to Phase 2 and later. Phase 1 builds and verifies a deterministic CLI foundation. The fixture command does not submit a proposal, authorize execution, evaluate evidence, or accept task completion.

Durable recording at every gate, hash-chain anchoring, transaction ordering, and crash recovery need separate proposed decisions. Phase 1 does not settle or weaken the existing guarantees.
