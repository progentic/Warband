# Phase 2 exit — deterministic authority core

**Owner decision, 2026-11-22.** Proto (Ian) accepts the bounded Phase 2 no-op authority core. This decision takes effect when the reviewed exit package merges to main. Meta concurred with exit on the measured envelope and the recorded limits. The tested runtime baseline is `2a8daa8c5865bf0121627f096425556c289c1924`. The exit package adds governance and documentation. [Source, targets and test inventory](../verification/phase2-crash-coverage.md#slice-6-evidence-inventory) · [Scoped requirements and evidence](../verification/traceability-matrix.md#phase-2-no-op-authority-core)

## Accepted behavior

On the isolated Linux target, a valid proposal obtained one permit. Its confirmed claim consumed the use. Only the issuing process could dispatch the no-op. A separately recorded observation and independently computed verdict supported one accepted transition, including under competing acceptors. Lost returns remained indeterminate. Replay reconstructed task and control state from custody-confirmed history. [Verification plan and results](../verification/phase2-verification-plan.md#fresh-runtime-dispatch-denial)

The ten crash points and storage faults are graded by the surviving bytes. A WAL commit sync failure left the exact pending event recoverable once. Corrupt custody history was preserved and service withheld. Proto rehearsed continued halt on the missing pledged event and unattested tail. [Fault evidence](../verification/phase2-crash-coverage.md#boundary-matrix) · [Operator decisions](../verification/phase2-crash-coverage.md#operator-reconciliation-rehearsal)

## Dispositions and remaining limits

- **WB-EXC-001 — expired at Phase 2 exit, 2026-11-22.** The owner and independent reviewer accepted administrative expiry. Technical closure was denied. The drain design is unimplemented. Preservation and exactly-once import of all observed denials under sustained input beyond the measured envelope remain unqualified. A future claim requires a new exception and separate successor qualification. [Reviewed ruling](../decisions/0008-phase2-resource-limits.md#owner-ruling-and-independent-disposition-2026-11-22)
- **Runner label.** The actionlint configuration registers the single compatibility label for version 1.7.12. The hosted job executed on Ubuntu 26.04. ADR-0006 remains Proposed; production promotion has its own gate. [Compatibility decision](../decisions/0006-hosted-linux-runner-compatibility.md)
- The 10,000-frame receipt-workload figure is a debit projection. Time and memory at that size are unmeasured. The one-task checkpoint and the dedicated runtime and cold-start boundary cases define the capacity evidence. [Capacity evidence](../verification/phase2-crash-coverage.md#cold-recovery-feasibility)
- Physical-media and power-loss durability remain unproven. The Linux targets are preproduction. The general effect qualification for `inspect_empty_store` remains unsettled beyond the isolated protected-directory enrollment protocol. Foundation debts retain their recorded later gates. [Effect graph](../decisions/0005-event-integrity-acceptance-and-recovery.md#6-proposed-phase-2-effect-qualification) · [Release obligations](PHASE_PLAN.md)

## Handoff

Phase 3 entry and implementation require separate explicit approval from Proto under ADR-0009. The next phase owes the real local CLI approval and the marker-file execution, observation and recovery proofs on its selected target. The `v0.1.0` tag and publication require separate authorization. [Accepted execution-boundary design](../decisions/0009-controlled-local-marker-execution.md)
