# ADR-0008 Phase 2 resource limits and denial-history exception

- **Status:** Accepted
- **Exception ID:** WB-EXC-001
- **Exception status:** Open
- **Exception owner:** Proto
- **Expires before phase:** 3
- **Independent reviewer:** Pending
- **Disposition record:** Pending
- **Review date:** 2026-11-11
- **Scope:** Phase 2 no-op custody, recovery and measurement
- **Supersedes:** None
- **Implementation authority:** Separate scope approval required

## Owner adoption recorded 2026-11-11

Proto directed adoption of the proposal and implementation, then explicitly approved an eight-file, up-to-150-added-line pure confirm increment. Acceptance covers the limits and exception proposal at `4d06963bbba493aa409a93063492576dd5c6347b`. The limits remain provisional. This owner decision permits progress while independent-reviewer assignment remains pending for exception closure or extension. The separately Proposed clock amendment retains its own acceptance gate. The [entry review](../engineering/phase2-entry-review.md) records the authorized code slice.

## Problem and exception

Rejected traffic can exhaust storage and recovery capacity. The [bounded-failure goal](../foundation/engineering-goals.md#bounded-failure) requires resource limits; [ADR-0005 Option A](0005-event-integrity-acceptance-and-recovery.md#option-a-bounded-durable-custody-rejection-receipt--selected-by-proto-2026-10-21) records Proto's accepted Phase 2 aggregate denial-growth limitation. WB-CON-007 and WB-INV-006 require complete security-event recording. Per-receipt bounds alone cannot resolve that tension.

WB-EXC-001 tracks that limitation for isolated Phase 2 verification with controlled local inputs. Proto owns remediation. Accepted-event history also grows, but this exception covers denial-triggered growth outside successful task admission. All history shares the recovery/storage envelope below; accepted-event growth needs its own supported capacity decision before production.

The structured fields above are the single current exception record. Review input from Meta was supplied by the project owner on 2026-11-11; reviewer eligibility remains unconfirmed. Review is due before effectful custody implementation authorization; expiry is Phase 2 exit, before Phase 3 entry, as adopted above. The checker conservatively rejects phase declarations at or beyond the expiry while the exception is open; supported-phase authorization remains separately enforced.

Closure requires an implemented successor design with a finite supported storage envelope derived from recovery scan, time and memory capacity. It must preserve custody continuity, every required receipt and exact-once import, provide an operator warning at a reviewed threshold below capacity, and pass saturation, sustained-denial, fsync-failure and interrupted-recovery cases. A published custody head alone is insufficient to resume projection replay from a trusted snapshot.

If closure cannot meet expiry, stop progression or obtain an explicit extension. Closure and extension require owner approval plus a named reviewer independent of the exception/fix author and owner, and a committed disposition with evidence, residual exposure and the next expiry gate. Update this ADR through review. The checker validates fields and disposition format; human review verifies provenance and independence. No extension is automatic.

## Provisional limits and outcomes

Acceptance records these values as provisional development limits. Before Phase 2 exit, measured evidence must confirm or revise every value through a recorded amendment, including target identity and rationale. Changes before that gate also require an amendment. Pure decisions receive supplied time, counters and limits; effectful coordinators enforce them.

| Resource | Provisional limit | Outcome |
| --- | --- | --- |
| Lock wait | 5 seconds, included in the operation deadline | LOCK_WAIT_EXCEEDED; preserve any existing pledge |
| Prepare/commit/confirm | 30 seconds including lock wait and at most 2 extra exact protocol-request attempts | OPERATION_DEADLINE_EXCEEDED; reconcile uncertain persistence before further mutation |
| Whole task | 180 seconds from admitted intent through confirmed acceptance, including all waits/retries | TASK_DEADLINE_EXCEEDED; withhold completion and reconcile partial work |
| Task scope | One no-op proposal, one capability use and one execution attempt per task | TASK_SCOPE_EXCEEDED; reject additional scope through the audited rejection path |
| Capability lifetime | 90 seconds of live elapsed time, covering 30-second issuance plus 30-second claim persistence and 30-second margin; clock binding requires the separate proposed ADR-0005 amendment | EXPIRED_CAPABILITY; require confirmed claim and dispatch before expiry |
| Execution retry | Zero automatic redispatches after uncertainty | Existing indeterminate/operator disposition |
| Recovery/replay | At most 100,000 total examined event/custody records and 60 seconds per invocation | RECOVERY_LIMIT_EXCEEDED; this invocation refuses readiness |
| Application memory | Runtime arena 128 MiB; custodian arena 8 MiB; allocation refusal | MEMORY_LIMIT_EXCEEDED; preserve history, withhold readiness/protected progress |
| SQLite memory | Runtime only, 64 MiB hard heap limit and 8 MiB connection cache budget; custodian has no SQLite | SQLITE_NOMEM; reconcile partial durable work |
| Process memory backstop | Runtime 256 MiB; custodian 32 MiB; cgroup v2 memory.max with swap disabled | PROCESS_MEMORY_TERMINATED; classify persisted state before progress |

Names introduced here are proposed coordinator diagnostics, outside ADR-0005's wire fault registry. Durable-state classification remains governed by ADR-0005. A timeout after PENDING without its event yields PENDING_EVENT_MISSING and operator-only reconciliation; storage failure yields CHECKPOINT_STORAGE_FAULT. Neither a deadline nor a memory refusal cancels a pledge or removes history. Audit diagnostic recording follows the existing available-storage rules.

Completion is allowed at exactly the record cap only if all required validation has finished before the time deadline; needing another record yields RECOVERY_LIMIT_EXCEEDED. Count repeated scans and receipt-import validation work. Every startup runs capped recovery and exposes its result through status and the existing diagnostic path. Readiness requires complete successful validation on that invocation. A store exceeding the visit cap fails again under the same configuration; timing or memory failures are reassessed with the same bounds.

Fresh stores follow ADR-0005's authorized genesis path. Recovery admission derives from the bounded scan of existing custody/history, with no persistent resource latch or clear operation. A memory-killed process is recovered through the same durable-state rules on its next start. Restart-loop scheduling belongs to later deployment supervision.

The 180-second task deadline is an outer bound; each nested operation receives the lesser of its own budget and remaining task time. Require elapsed-time enforcement immune to wall-clock changes, rejection on clock failure/regression, and reconciliation of tasks in flight after restart. The [proposed ADR-0005 clock amendment](0005-event-integrity-acceptance-and-recovery.md#proposed-adr-0008-amendment-review) defines incarnation and expiry semantics for separate acceptance before live capability implementation. Limits and exception acceptance can proceed separately. OS-blocked writes may finish after deadlines; reconcile uncertain outcomes before progress.

## Capacity and closure review

Evaluate a supported finite store envelope with operator archive-and-new-store handoff before snapshots/resume. ADR-0005 genesis enrolls an empty store but has no typed predecessor-head handoff or archive-verification procedure. A free-text reason cannot prove continuity. A successor design must bind and verify the archived store's final trusted head, preserve evidence, resolve pending pledges/imports and define task disposition across distinct stores. Epoch rotation alone cannot bound recovery because custody ordinals and authorization uniqueness span retained history. Until a verified closure path exists, plan for a reviewed extension or stop at expiry.

Propose CAPACITY_WARNING as a status field at an estimated 80,000 visits. Anchor the estimate to the exact visit count and validated metadata from the last successful recovery in this process. Apply conservative factors only to custody-ordinal/event growth since that observation, including denial frames, repeated scans and import amplification. The observation is volatile diagnostic data; every restart recomputes recovery. A changed epoch, scan algorithm or workload invalidates the estimate unless its factors cover that change. Unknown factors, missing observations or checked-arithmetic overflow report CAPACITY_UNKNOWN. The estimate never substitutes for recovery validation.

At slice 4 completion, measure visits per confirmed event and bytes per denial. At slice 5 completion, measure visits per task and establish a provisional tasks-per-store envelope before slice 6. Record any revised limit as an amendment; Phase 2 exit retains final confirmation. Reviewer eligibility is unconfirmed; the owner adoption above defers assignment to closure or extension, which require independent review.

## Target, review and verification

The accepted development verification profile is Ubuntu 24.04 x64 with the repository's locked Linux toolchain, local ext4 storage and SQLite's default Unix VFS with WAL/FULL. Proto owns selection and must record the exact image/kernel, disk, mount options, VM/cache/flush profile and enforcement configuration before effectful custody authorization. Acceptance approves this proposed development profile, including cgroup v2 enforcement. Exact image/kernel/storage details are due before effectful authorization; the current VM selection file does not establish them. This is a development verification profile; production selection retains its later gate.

Use bounded arenas for application allocations, configure and query sqlite3_hard_heap_limit64 and cache_size, and record cgroup limits and actual memory including native/SQLite overhead. The hard heap cap is process-wide; cache size is advisory. Prove allocation refusal and cgroup termination separately. Retained-history saturation follows ADR-0005's storage-fault disposition; audit-preserving capacity/admission or retention mechanisms require successor design review.

The [verification plan](../verification/phase2-verification-plan.md#proposed-limits-and-measurement) supplies per-limit cases and measurement workloads. Owner adoption accepts exception ownership, provisional values and the development profile/enforcement proposal; independent review remains required for closure or extension. Runtime contract and negative-path alignment accompanies implementation authorization. Expiry extends only through the independently reviewed disposition above; provisional-value confirmation and exception closure are separate Phase 2 exit requirements.
