# Phase 3 entry — controlled local execution

**Entry authorized by Proto (Ian), 2026-11-22. Execution-boundary owner: Proto (Ian).** The accepted Phase 2 exit is on main at `a975149635948821fdd0aa421b26c393d9785f51`. The selected target is Linux x86-64 on preproduction `x64-review`. [Phase 2 exit](../governance/phase2-exit.md) · [Phase 3 entry gates](../governance/PHASE_PLAN.md#phase-3-controlled-local-execution)

## Entry decisions and first increment

| Gate | Decision |
|---|---|
| Local effect | One exclusive creation at a fixed name in a runtime-controlled attempt directory. The broker retains the directory descriptor. [Action contract](../decisions/0009-controlled-local-marker-execution.md#marker-and-approval-contract) |
| Worker profile | At most 4,096 payload bytes, five seconds of worker time, 32 MiB with zero swap, and 4,096 bytes of combined output. Each sandbox control has a matching-kernel test. [Selected profile](../decisions/0009-controlled-local-marker-execution.md#selected-x64-review-worker-profile) |
| Approval | The operator uses the real local CLI. The runtime records the decision against the exact normalized proposal and its Phase 2 identities. [Approval and recovery proof plan](../decisions/0009-controlled-local-marker-execution.md#verification) |
| First increment | Record entry and specify the proposed marker event encodings, binding checks and compatibility vectors. [Accepted wire profile 1](../decisions/0009-controlled-local-marker-execution.md#marker-event-wire-profile-1) |

The initial entry authorization covered two documentation files. The subsequent pure codec and replay increments retained the Phase 2 declaration.

- **Runtime activation:** Proto authorized proposal intake on 2026-11-23.

The project and test manifest now declare Phase 3. The `marker-intake` Linux command takes up to 4,096 nonsecret payload bytes on stdin and accepts zero command-line arguments. Launch it as the runtime UID in the trusted root-owned store directory. Provision a runtime-owned mode-0700 `attempts/` beside `journal/` and `endpoints/`. Install `intake.anchor` as a root-owned regular file with no group or other write permission. Its 68 bytes are the authenticated initial epoch-1 checkpoint (store, epoch, zero sequence, genesis head) followed by the trusted custodian UID as little-endian u32.

The command creates the task and proposal under the writer gate. It reports the confirmed Ref, fingerprint, length, payload digest and projected versions. The runtime returns the held directory descriptor with this result; the standalone command closes it on exit. Restart may complete an exact stored pledge and report RecoveredConfirmation. An old pathname or matching inode cannot restore a prior execution’s live authority.

## Review a marker proposal

In the trusted store directory, install a root-owned regular file named `approval.ids` containing the runtime UID and operator UID as two little-endian u32s. Give both users read access and reserve write access for root. Use distinct non-root identities for runtime, operator and custodian. Both commands use this directory as their working directory.

1. As the runtime UID, run `marker-approval serve < payload`. It performs intake and keeps the original attempt directory open while the operator reviews the confirmed proposal.
2. As the operator UID, run `marker-approval decide`. Check the proposal Ref, task/run, attempt, fixed marker target, directory identity, versions, length and full SHA-256. Enter `approve` or `reject`. Both programs check the peer UID on their Linux Unix-domain connection. The runtime reacquires the writer gate and rechecks operator registration, custody, the displayed binding and directory continuity.
3. Save the decision Ref. An affirmative decision permits one use at task/control **1/1**. A rejection stays at **1/0**. This command ends before claim and leaves the marker absent.

For a lost acknowledgment, run `marker-approval receipts` as the runtime and repeat the same decision through `decide` as the operator. The receipt service reports the confirmed task/control versions. An exact retry returns the recorded decision Ref. A matching pending SQLite row may receive its original confirmation. Receipt recovery carries no live grant. A missing pledged event, unconfirmed integrity, or a lost directory binding requires reconciliation. [Target evidence](../verification/traceability-matrix.md#operator-decision-and-permit)

## Stop at the broker handoff

On preproduction x64-review, use `marker-approval gate < payload` as the runtime and `marker-approval decide` as the operator. Approval still acknowledges the decision Ref. The issuer then confirms one kind-14 claim, checks the offered operation against custody under the writer gate, and reports the full claim Ref, attempt and request digest at the handoff. This command ends there. The existing `serve` mode ends at permit issuance.

A confirmed refusal leaves the task incomplete and the claim consumed. Preserve an occupied marker. If the issuer reports `RefusalUnconfirmed`, inspect custody and SQLite before any further progress. Receipt recovery can confirm an exact historical row and reports the original approval Ref. [Target evidence](../verification/traceability-matrix.md#post-claim-marker-gate)

## Evidence owed

Meta independently reproduced the proposal and linked approval vectors from the specification. Proto accepted wire profile 1 on 2026-11-22. The separately authorized pure codecs for kinds 11/12 passed the [proposal, approval and v1 compatibility cases](../decisions/0009-controlled-local-marker-execution.md#proposal-and-approval-codec-qualification). The [mixed-history replay](../verification/traceability-matrix.md#marker-chain-replay) verifies confirmed constructed marker chains. WB-INV-007 has live CLI evidence through permit. WB-NEG-008 has post-claim gate evidence. The worker still requires matching-kernel sandbox verification. Later target qualification must establish both the lost-reply verdict after worker stop and the independent second-create result while the marker remains in place. Record the source, kernel, effective limits and custody references with those runs.
