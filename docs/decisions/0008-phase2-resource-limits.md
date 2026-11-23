# ADR-0008 Phase 2 resource limits and denial-history exception

- **Status:** Accepted
- **Exception ID:** WB-EXC-001
- **Exception status:** Open
- **Exception owner:** Proto
- **Expires before phase:** 3
- **Independent reviewer:** Meta
- **Disposition record:** Stop at expiry — https://github.com/progentic/Warband/commit/50f1bd4fc1e171b7da07d04970a94afba704d2fd
- **Review date:** 2026-11-21
- **Scope:** Phase 2 no-op custody, recovery and measurement
- **Supersedes:** None
- **Implementation authority:** Separate scope approval required

## Owner adoption recorded 2026-11-11

Proto directed adoption of the proposal and implementation, then explicitly approved an eight-file, up-to-150-added-line pure confirm increment. Acceptance covers the limits and exception proposal at `4d06963bbba493aa409a93063492576dd5c6347b`. The limits remain provisional. At adoption, the owner permitted progress and deferred reviewer assignment. The [entry review](../engineering/phase2-entry-review.md) records the authorized code slice.

## Problem and exception

Rejected traffic can exhaust storage and recovery capacity. The [bounded-failure goal](../foundation/engineering-goals.md#bounded-failure) requires resource limits; [ADR-0005 Option A](0005-event-integrity-acceptance-and-recovery.md#option-a-bounded-durable-custody-rejection-receipt--selected-by-proto-2026-10-21) records Proto's accepted Phase 2 aggregate denial-growth limitation. WB-CON-007 and WB-INV-006 require complete security-event recording. Per-receipt bounds alone cannot resolve that tension.

WB-EXC-001 tracks that limitation for isolated Phase 2 verification with controlled local inputs. Proto owns remediation. Accepted-event history also grows, but this exception covers denial-triggered growth outside successful task admission. All history shares the recovery/storage envelope below; accepted-event growth needs its own supported capacity decision before production.

The structured fields above are the single current exception record. Review input from Meta was supplied by the project owner on 2026-11-11; eligibility was unconfirmed at that review. Review is due before effectful custody implementation authorization; expiry is Phase 2 exit, before Phase 3 entry, as adopted above. The checker conservatively rejects phase declarations at or beyond the expiry while the exception is open; supported-phase authorization remains separately enforced.

On 2026-11-18 Proto completed the pre-implementation review and accepted carrying WB-EXC-001 into isolated 3b testing with controlled local inputs. Each observed denial adds a durable 203-byte frame and later import work. Aggregate growth can exhaust disk or exceed the recovery visit/time budget and withhold readiness. Preserve required audit records and the storage-fault disposition. The exception stays Open, owned by Proto, with the existing Phase 2 exit deadline and independent review required for closure or extension.

Closure requires an implemented successor design with a finite supported storage envelope derived from recovery scan, time and memory capacity. It must preserve custody continuity, every required receipt and exact-once import, provide an operator warning at a reviewed threshold below capacity, and pass saturation, sustained-denial, fsync-failure and interrupted-recovery cases. A published custody head alone is insufficient to resume projection replay from a trusted snapshot.

The original alternatives at expiry were to stop progression or obtain an explicit extension. Closure and extension require owner approval plus a named reviewer independent of the exception/fix author and owner, and a committed disposition with evidence, residual exposure and the next expiry gate. Update this ADR through review. The checker validates fields and disposition format; human review verifies provenance and independence. No extension is automatic.

## Isolated target ruling and reviewer assignment

On 2026-11-21 Proto accepted loss of availability at a finite limit on x64-review and selected controlled halt at the custodian as the successor design to qualify. Stop admitting new work before observing another denial-generating request. Preserve every already-observed request's required receipt, including across interrupted writes, and retain the evidence for exactly-once import. Before implementation, derive a hard admission bound and reserve for in-flight work, import and a full recovery pass under the disk, visit, time and memory limits. The measured 203-byte receipt and placement-specific 142 additional examinations inform this calculation. They do not establish a worst-case reserve.

Meta accepted the independent disposition review and attests to being neither the owner, the exception author nor the fix author. Proto is the project owner’s developer alias. At disposition, document provenance and verify independence from Proto and the exception and fix authors. Proto retains owner approval. Meta subsequently concurred in the stop-at-expiry decision below.

### Hard admission reserve (draft for independent review)

Evaluate admission at the custodian before accepting another connection on either listener. The single synchronous serve loop accepts one connection, completes one request and closes it before serving another. At the pre-accept boundary there are zero accepted requests in flight. While serving there is at most one. Reserve its worst permitted outcome before accept, including a 203-byte denial if required. Kernel-queued connections have not entered the handler. Review this observation boundary explicitly against Option A. Missing, inconsistent or overflowing local accounting closes admission.

For a candidate trigger, let U bound all unimported denials after draining that handler. The custodian cannot infer the SQLite watermark from its tip. Until a verified tighter bound exists, count every retained denial as potentially outstanding. Drain requires up to U confirmed import events and 2U custody frames. For an enrolled store without a pending pledge, those frames add 502U logical custody bytes. Include already-pending work, enrollment if needed, and any interrupted append separately. Bound allocated SQLite database, index and peak WAL space, temporary head publication and filesystem headroom on the selected stack. Post-close WAL samples cannot supply that peak.

For each reachable history at the trigger, price the in-flight outcome, every remaining import and one complete recovery over the resulting largest history. Include repeated custody validation, cursor walks, retained segments, event-prefix reads and read-back. Show actual visits and production debits, per-invocation elapsed time and peak memory in each process. Sum disk growth, account for overlapping allocations, and check the existing per-invocation limits individually. A successful bounded drain requires a way for verify/prepare/confirm to finish after general admission closes while further denial-generating input stays quiesced. Ordinary authenticated inputs can themselves be malformed. An unrestricted runtime socket cannot establish this condition.

**Decision pending.** Approve a numerical hard bound only when all four reserves fit for the same declared envelope, including a safe way to complete the drain under sustained offered input. The 80,000 warning threshold is an estimate in visits. Its distance from the 100,000 per-invocation limit supplies no disk, time or memory guarantee. Record unknown terms as blockers. Storage faults retain the zero-receipt, no-progress disposition until reconciliation. Saturation and fault runs follow review of the bound.

#### Candidate cutoff calculation for Meta (paper review)

**Meta’s paper-review decision (2026-11-21): numerical approval withheld.** Meta accepted this calculation as a review record. Evaluate 90,000 as a candidate ceiling on projected production debits for the most expensive required invocation after admission. Before accepting a connection, include the worst permitted result of that connection. Refuse general admission if the projection would exceed the candidate or any required input is unknown. The existing 100,000 ceiling applies to each invocation. For this candidate, anchor the warning to exact successful-recovery work and validated metadata, then project in the same charged-debit units as the cutoff. Keep the actual examination count separately identifiable.

The following worked case prices an enrolled epoch-1 store with only GENESIS and n durable, unimported denials, no pending pledge, no accepted task and no new external traffic during drain. After import it holds n events and 1+3n custody frames. For n ≥ 1 the first pass verifies once, then prepares, confirms and verifies once per denial. The final clean pass verifies n+1 times at the final tip. Counting the [Slice 4 loops](../verification/slice4-capacity.md) gives import examinations (13n²+27n)/2+1 and import debits (25n²+33n)/2+3. Clean-pass examinations are (7n²+25n)/2+2 and debits are (n+1)(6n+3)+n. These reproduce the recorded one- and fifty-receipt results. Larger rows are calculations only.

| n after drain of admitted handler | Import actual / debits | Final clean pass actual / debits | Candidate visit gate |
| ---: | ---: | ---: | --- |
| 80 | 42,681 / 81,323 | 23,402 / 39,203 | Within 90,000 charged |
| 84 | 46,999 / 89,589 | 25,748 / 43,179 | Last admissible n for this case |
| 85 | 48,111 / 91,718 | 26,352 / 44,203 | Refuse before accepting the 85th potential denial |
| 89 | 52,689 / 100,484 | 28,838 / 48,419 | Import would exceed the existing ceiling |

At 83 prior denials the single accepted handler could consume 203 more bytes and examine 84 history frames to record denial 84. Import then adds 42,168 bytes (168 pledge frames). Final custody history occupies 59,391 logical bytes including the 171-byte fixture genesis. The import and final clean pass together cost 132,768 debits across two invocations. Each must finish within its own limits. At 84 denials the import examinations are still below 80,000 even as debits approach 90,000. A warning calibrated only to examinations would arrive too late. In this shape projected import debits first cross 80,000 at denial 80 (79,319 at 79). Re-review requires proof of conservative charged-unit projection and notice before general admission closes.

| Reserve term | Evidence needed for a pass |
| --- | --- |
| Admission and drain | Specify how both general listeners stop before accept, how queued clients are disconnected, and how an exclusive drain path completes outstanding imports without admitting new denial-generating traffic. Account for interrupted accepted requests before the first durable receipt byte exists. A zero-receipt storage fault withholds acknowledgment but cannot reconstruct lost request bytes. Open design terms. |
| Visits | The worked case fits two separate invocations. Bound custodian startup scanning and all permitted histories, including valid non-denial operations, mixed task/denial traffic, live pledges and retained segments, or enforce a narrower declared envelope before admission. The custodian needs validated local bounds for each input. Unknown for the full envelope. |
| Disk | Reserve allocated blocks for growth on both stores, peak WAL and its companion, indexes, temporary publication and interrupted writes. The endpoint measurements and 59,391-byte custody calculation do not bound peak allocation or guarantee free space. Unknown. |
| Time | Establish that supported drain and recovery complete within the operation and recovery deadlines on the selected stack. A timed-out or blocked fsync requires the storage-fault disposition. Unknown at saturation. |
| Memory | Bound peak simultaneous buffers, decoded metadata, process overhead, and SQLite heap/cache against each component and cgroup ceiling. A small final file length and configured memory limits alone do not demonstrate successful recovery. Unknown at saturation. |

Meta's review gate is a bound covering every permitted state in all four resource dimensions, plus an auditable drain under sustained offered input. Until those conditions hold, the candidate and the 84-denial example grant no admission authority. Settle the durable observation boundary, drain isolation and reachable history shapes by design before submitting a physical saturation measurement plan. This review authorizes neither implementation nor fault runs.

## Final disposition: stop at expiry (2026-11-21)

Proto, project owner, approved **stop at expiry**. Meta, the independent reviewer, concurred. Closure was requested, reviewed and denied on the current evidence. This decision supersedes the extension recommendation. WB-EXC-001 remains Open and expires at Phase 2 exit. While it is open, withhold the Phase 2 exit record and block Phase 3 entry. Reconsideration requires a new recorded owner ruling and a new independent reviewer disposition.

Successor qualification proceeds alongside Slice 6. Closure requires an approved and implemented custodian drain with enforceable history restrictions, numerical approval of disk, visit, elapsed-time and memory reserves for the same envelope, and evidence of warning delivery and the prescribed operator action. Review the saturation, sustained-denial, fsync-failure and interrupted-recovery runs against that envelope, including receipt continuity and exactly-once import. Until closure is granted on that evidence, Slice 6 exit traceability must carry WB-EXC-001 as an open Phase 2 exit blocker.

### Owner ruling and independent disposition, 2026-11-22

Proto approved ending Phase 2 on the bounded, verified no-op core. Meta concurred as the independent reviewer identified above. Meta credited the evidence for custody continuity, exactly-once receipt import and bounded recovery. The review excluded a sustained-denial storage guarantee beyond the measured workload.

This ruling supersedes the November 21 requirement to withhold the Phase 2 exit record until successor qualification. On merge of the reviewed exit package, WB-EXC-001 expires at Phase 2 exit. Technical closure was denied and is no longer sought for Phase 2. The custodian drain remains unimplemented. The development limits and the measured one-task envelope stand. A future sustained-load envelope claim requires a new exception and separate qualification of admission, drain, reserves, warning delivery and fault recovery. Phase 3 entry requires separate explicit approval from Proto after the exit record.

## Provisional limits and outcomes

Acceptance records these values as provisional development limits. Before Phase 2 exit, measured evidence must confirm or revise every value through a recorded amendment, including target identity and rationale. Changes before that gate also require an amendment. Pure decisions receive supplied time, counters and limits; effectful coordinators enforce them.

| Resource | Provisional limit | Outcome |
| --- | --- | --- |
| Lock wait | 5 seconds, included in the operation deadline | LOCK_WAIT_EXCEEDED; preserve any existing pledge |
| Prepare/commit/confirm | 30 seconds including lock wait and at most 2 extra exact protocol-request attempts | OPERATION_DEADLINE_EXCEEDED; reconcile uncertain persistence before further mutation |
| Whole task | 180 seconds from admitted intent through confirmed acceptance, including all waits/retries | TASK_DEADLINE_EXCEEDED; withhold completion and reconcile partial work |
| Task scope | One no-op proposal, one capability use and one execution attempt per task | TASK_SCOPE_EXCEEDED; reject additional scope through the audited rejection path |
| Capability lifetime | 90 seconds of live elapsed time, covering 30-second issuance plus 30-second claim persistence and 30-second margin; Linux clock binding follows the [accepted amendment](0005-event-integrity-acceptance-and-recovery.md#accepted-live-capability-clock-amendment) | EXPIRED_CAPABILITY; require confirmed claim and dispatch before expiry |
| Execution retry | Zero automatic redispatches after uncertainty | Existing indeterminate/operator disposition |
| Recovery/replay | At most 100,000 charged visits per runtime session; 60 seconds per recovery invocation | RECOVERY_LIMIT_EXCEEDED; this invocation refuses readiness |
| Application memory | Runtime arena 128 MiB; custodian arena 8 MiB; allocation refusal | MEMORY_LIMIT_EXCEEDED; preserve history, withhold readiness/protected progress |
| SQLite memory | Runtime only, 64 MiB hard heap limit and 8 MiB connection cache budget; custodian has no SQLite | SQLITE_NOMEM; reconcile partial durable work |
| Process memory backstop | Runtime 256 MiB; custodian 32 MiB; cgroup v2 memory.max with swap disabled | PROCESS_MEMORY_TERMINATED; classify persisted state before progress |

Names introduced here are proposed coordinator diagnostics, outside ADR-0005's wire fault registry. Durable-state classification remains governed by ADR-0005. A timeout after PENDING without its event yields PENDING_EVENT_MISSING and operator-only reconciliation; storage failure yields CHECKPOINT_STORAGE_FAULT. Neither a deadline nor a memory refusal cancels a pledge or removes history. Audit diagnostic recording follows the existing available-storage rules.

Under [Proto’s 2026-11-22 verification amendment](../verification/phase2-verification-plan.md#cold-recovery-readiness-and-visit-ownership), a runtime recovery session can complete at exactly 100,000 debits when validation finishes before its deadline. A charge exceeding the remaining budget yields RECOVERY_LIMIT_EXCEEDED for that invocation. Count repeated scans and receipt-import work and report actual examinations separately. Custodian startup validates the retained input under its history-size, memory and time limits before serving requests. The verification plan records distinct proofs for those limits.

Fresh stores follow ADR-0005's authorized genesis path. Recovery admission derives from the bounded scan of existing custody/history, with no persistent resource latch or clear operation. A memory-killed process is recovered through the same durable-state rules on its next start. Restart-loop scheduling belongs to later deployment supervision.

The 180-second task deadline is an outer bound; each nested operation receives the lesser of its own budget and remaining task time. Require elapsed-time enforcement immune to wall-clock changes, rejection on clock failure/regression, and reconciliation of tasks in flight after restart. The [accepted ADR-0005 clock amendment](0005-event-integrity-acceptance-and-recovery.md#accepted-live-capability-clock-amendment) defines incarnation and expiry semantics. Live implementation requires separate authorization. OS-blocked writes may finish after deadlines; reconcile uncertain outcomes before progress.

### Slice 5 supplied-clock decisions

On 2026-11-21 Proto approved a pure timing check over supplied elapsed milliseconds. Task admission starts the outer budget. An operation keeps its original start through lock waits and exact retries. A lock wait also has its own start. Capability timing uses its supplied original start and the outer task budget. Claim confirmation and dispatch each require a fresh check.

The check returns the least remaining time across the applicable budgets. Equality expires a deadline. If several limits have expired, report the outermost one. Missing or out-of-order required observations take precedence and yield zero remaining time. Subtracting validated ticks avoids overflow when the origin is near the maximum tick. A within-deadline result establishes only the timing prerequisite. Attempt-count enforcement belongs to the coordinator.

Four focused Odin tests cover strict boundaries, invalid observations, nested retry budgets and expiry between confirmation and dispatch. The first compile failed before test execution on enum-indexed array syntax and variable indexing of a constant. The corrected package passed on macOS ARM64 with the pinned compiler. The live clock amendment remains Proposed.

## Capacity and closure review

Evaluate a supported finite store envelope with operator archive-and-new-store handoff before snapshots/resume. ADR-0005 genesis enrolls an empty store but has no typed predecessor-head handoff or archive-verification procedure. A free-text reason cannot prove continuity. A successor design must bind and verify the archived store's final trusted head, preserve evidence, resolve pending pledges/imports and define task disposition across distinct stores. Epoch rotation alone cannot bound recovery because custody ordinals and authorization uniqueness span retained history. The stop-at-expiry ruling governs progression while this exception remains open.

Propose CAPACITY_WARNING as a status field at an estimated 80,000 visits. Anchor the estimate to the exact visit count and validated metadata from the last successful recovery in this process. Apply conservative factors only to custody-ordinal/event growth since that observation, including denial frames, repeated scans and import amplification. The observation is volatile diagnostic data; every restart recomputes recovery. A changed epoch, scan algorithm or workload invalidates the estimate unless its factors cover that change. Unknown factors, missing observations or checked-arithmetic overflow report CAPACITY_UNKNOWN. The estimate never substitutes for recovery validation.

At slice 4 completion, measure visits per confirmed event and bytes per denial. At slice 5 completion, measure visits per task and establish a provisional tasks-per-store envelope before slice 6. Record any revised limit as an amendment; Phase 2 exit retains final confirmation. Closure requires independent review of the successor evidence.

## Target, review and verification

The accepted development verification profile is Ubuntu 24.04 x64 with the repository's locked Linux toolchain, local ext4 storage and SQLite's default Unix VFS with WAL/FULL. Proto owns selection and must record the exact image/kernel, disk, mount options, VM/cache/flush profile and enforcement configuration before effectful custody authorization. Acceptance approves this proposed development profile, including cgroup v2 enforcement. Exact image/kernel/storage details are due before effectful authorization; the current VM selection file does not establish them. This is a development verification profile; production selection retains its later gate.

Use bounded arenas for application allocations, configure and query sqlite3_hard_heap_limit64 and cache_size, and record cgroup limits and actual memory including native/SQLite overhead. The hard heap cap is process-wide; cache size is advisory. Prove allocation refusal and cgroup termination separately. Retained-history saturation follows ADR-0005's storage-fault disposition; audit-preserving capacity/admission or retention mechanisms require successor design review.

The [verification plan](../verification/phase2-verification-plan.md#proposed-limits-and-measurement) supplies per-limit cases and measurement workloads. Owner adoption accepts exception ownership, provisional values and the development profile/enforcement proposal; independent review remains required for closure or extension. Runtime contract and negative-path alignment accompanies implementation authorization. The current disposition fixes expiry at Phase 2 exit; provisional-value confirmation and exception closure are separate Phase 2 exit requirements.
