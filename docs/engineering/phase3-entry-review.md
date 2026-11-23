# Phase 3 entry — controlled local execution

**Entry authorized by Proto (Ian), 2026-11-22. Execution-boundary owner: Proto (Ian).** The accepted Phase 2 exit is on main at `a975149635948821fdd0aa421b26c393d9785f51`. The selected target is Linux x86-64 on preproduction `x64-review`. [Phase 2 exit](../governance/phase2-exit.md) · [Phase 3 entry gates](../governance/PHASE_PLAN.md#phase-3-controlled-local-execution)

## Entry decisions and first increment

| Gate | Decision |
|---|---|
| Local effect | One exclusive creation at a fixed name in a runtime-controlled attempt directory. The broker retains the directory descriptor. [Action contract](../decisions/0009-controlled-local-marker-execution.md#marker-and-approval-contract) |
| Worker profile | At most 4,096 payload bytes, five seconds of worker time, 32 MiB with zero swap, and 4,096 bytes of combined output. Each sandbox control has a matching-kernel test. [Selected profile](../decisions/0009-controlled-local-marker-execution.md#selected-x64-review-worker-profile) |
| Approval | The operator uses the real local CLI. The runtime records the decision against the exact normalized proposal and its Phase 2 identities. [Approval and recovery proof plan](../decisions/0009-controlled-local-marker-execution.md#verification) |
| First increment | Record entry and specify the proposed marker event encodings, binding checks and compatibility vectors. [Accepted wire profile 1](../decisions/0009-controlled-local-marker-execution.md#marker-event-wire-profile-1) |

The initial entry authorization covered two documentation files. The executable phase declaration and test manifest still describe the implemented Phase 2 runtime. Activation of Phase 3 in those files and its governance checks requires an implementation increment. Worker and broker implementation and the `v0.1.0` tag each require separate authorization.

## Evidence owed

Meta independently reproduced the proposal and linked approval vectors from the specification. Proto accepted wire profile 1 on 2026-11-22. The separately authorized pure codecs for kinds 11/12 passed the [proposal, approval and v1 compatibility cases](../decisions/0009-controlled-local-marker-execution.md#proposal-and-approval-codec-qualification). Positive marker-chain replay requires the remaining records and reference rules. WB-INV-007 and WB-NEG-008 still need the positive CLI path and rejection before dispatch on the actual execution path. Later target qualification must establish both the lost-reply verdict after worker stop and the independent second-create result while the marker remains in place. Record the source, kernel, effective limits and custody references with those runs.
