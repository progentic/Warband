# ADR-0008 Phase 2 resource limits and denial-history exception

- **Status:** Proposed
- **Exception ID:** WB-EXC-001
- **Exception status:** Open
- **Exception owner:** Proto
- **Expires before phase:** 3
- **Independent reviewer:** Pending
- **Disposition record:** Pending
- **Review date:** 2026-11-11
- **Scope:** Phase 2 no-op custody, recovery and measurement
- **Supersedes:** None while Proposed
- **Implementation authority:** Separate scope approval required

## Problem and exception

Rejected traffic can exhaust storage and recovery capacity. The [bounded-failure goal](../foundation/engineering-goals.md#bounded-failure) requires resource limits; [ADR-0005 Option A](0005-event-integrity-acceptance-and-recovery.md#option-a-bounded-durable-custody-rejection-receipt--selected-by-proto-2026-10-21) records Proto's accepted Phase 2 aggregate denial-growth limitation. WB-CON-007 and WB-INV-006 require complete security-event recording. Per-receipt bounds alone cannot resolve that tension.

WB-EXC-001 tracks that limitation for isolated Phase 2 verification with controlled local inputs. Proto owns remediation. Accepted-event history also grows, but this exception covers denial-triggered growth outside successful task admission. All history shares the recovery/storage envelope below; accepted-event growth needs its own supported capacity decision before production.

The structured fields above are the single current exception record. Review is due before effectful custody implementation authorization; proposed expiry is Phase 2 exit, before Phase 3 entry. While this ADR is Proposed, these additions await owner acceptance. The checker conservatively rejects phase declarations at or beyond the expiry while the exception is open; supported-phase authorization remains separately enforced.

Closure requires an implemented successor design with a finite supported storage envelope derived from recovery scan, time and memory capacity. It must preserve custody continuity, every required receipt and exact-once import, provide an operator warning at a reviewed threshold below capacity, and pass saturation, sustained-denial, fsync-failure and interrupted-recovery cases. A published custody head alone is insufficient to resume projection replay from a trusted snapshot.

If closure cannot meet expiry, stop progression or obtain an explicit extension. Closure and extension require owner approval plus a named reviewer independent of the exception/fix author and owner, and a committed disposition with evidence, residual exposure and the next expiry gate. Update this ADR through review. The checker validates fields and disposition format; human review verifies provenance and independence. No extension is automatic.

## Provisional limits and outcomes

Acceptance records these values as provisional development limits. Before Phase 2 exit, measured evidence must confirm or revise every value through a recorded amendment, including target identity and rationale. Changes before that gate also require an amendment. Pure decisions receive supplied time, counters and limits; effectful coordinators enforce them.

| Resource | Proposed limit | Outcome |
| --- | --- | --- |
| Lock wait | 5 seconds, included in the operation deadline | LOCK_WAIT_EXCEEDED; preserve any existing pledge |
| Prepare/commit/confirm | 30 seconds including lock wait and at most 2 extra exact protocol-request attempts | OPERATION_DEADLINE_EXCEEDED; reconcile uncertain persistence before further mutation |
| Whole task | 180 seconds from admitted intent through confirmed acceptance, including all waits/retries | TASK_DEADLINE_EXCEEDED; withhold completion and reconcile partial work |
| Task scope | One no-op proposal, one capability use and one execution attempt per task | TASK_SCOPE_EXCEEDED; reject additional scope through the audited rejection path |
| Capability lifetime | 90 seconds from recorded authorization time, covering 30-second issuance plus 30-second claim persistence and 30-second margin | EXPIRED_CAPABILITY; require confirmed claim and dispatch before expiry |
| Execution retry | Zero automatic redispatches after uncertainty | Existing indeterminate/operator disposition |
| Recovery/replay | At most 100,000 total examined event/custody records and 60 seconds per invocation | RECOVERY_LIMIT_EXCEEDED; terminal halt under current configuration |
| Application memory | 128 MiB bounded arena per process; allocation refusal | MEMORY_LIMIT_EXCEEDED; preserve history, withhold readiness/protected progress |
| SQLite memory | 64 MiB hard heap limit, 8 MiB connection cache budget | SQLITE_NOMEM; reconcile partial durable work |
| Process memory backstop | 256 MiB cgroup v2 memory.max per process, swap disabled | PROCESS_MEMORY_TERMINATED; classify persisted state before progress |

Names introduced here are proposed coordinator diagnostics, outside ADR-0005's wire fault registry. Durable-state classification remains governed by ADR-0005. A timeout after PENDING without its event yields PENDING_EVENT_MISSING and operator-only reconciliation; storage failure yields CHECKPOINT_STORAGE_FAULT. Neither a deadline nor a memory refusal cancels a pledge or removes history. Audit diagnostic recording follows the existing available-storage rules.

Completion is allowed at exactly the record cap only if all required validation has finished before the time deadline; needing another record yields RECOVERY_LIMIT_EXCEEDED. Count repeated scans and receipt-import validation work. Both limit exhaustion and recovery memory failure latch a supervisor-visible halted state with zero automatic restarts. Reboot must preserve the latch; absence or uncertainty about it withholds readiness. Operator restart requires a reviewed capacity change or verified recovery procedure, never another identical capped scan or an unverified cursor. Latch persistence/enforcement is an implementation prerequisite with fault tests.

The 180-second task deadline is an outer bound; each nested operation receives the lesser of its own budget and remaining task time. Expiry is immutable in the authorization event and checked at claim and dispatch. OS-blocked writes can finish after deadlines; their results remain uncertain until reconciled. Deadline passage grants no permission to acknowledge, dispatch or claim completion.

## Target, review and verification

Proposed verification target is Ubuntu 24.04 x64 with the repository's locked Linux toolchain, local ext4 storage and SQLite's default Unix VFS with WAL/FULL. Proto owns selection and must record the exact image/kernel, disk, mount options, VM/cache/flush profile and enforcement configuration before effectful custody authorization. Selection awaits ADR acceptance; the current VM selection file does not establish this target. This is a development verification profile; production selection retains its later gate.

Use bounded arenas for application allocations, configure and query sqlite3_hard_heap_limit64 and cache_size, and record cgroup limits and actual memory including native/SQLite overhead. The hard heap cap is process-wide; cache size is advisory. Prove allocation refusal and cgroup termination separately. Retained-history saturation follows ADR-0005's storage-fault disposition; audit-preserving capacity/admission or retention mechanisms require successor design review.

The [verification plan](../verification/phase2-verification-plan.md#proposed-limits-and-measurement) supplies per-limit cases and measurement workloads. Acceptance requires exception owner/reviewer assignment, provisional values, target and enforcement approval. Runtime contract and negative-path alignment accompanies implementation authorization. Expiry extends only through the independently reviewed disposition above; provisional-value confirmation and exception closure are separate Phase 2 exit requirements.
