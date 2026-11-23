# Controlled halt on x64-review: decisions for re-review

Archived, unimplemented successor proposal. The [November 22 disposition](../decisions/0008-phase2-resource-limits.md#owner-ruling-and-independent-disposition-2026-11-22) records the bounded Phase 2 exit. A future proposal for sustained-load qualification must establish its own exception and envelope.

## Admission and observation

Apply [Rule A under WB-CON-007](../decisions/0005-event-integrity-acceptance-and-recovery.md#rule-a-interrupted-denial-recording-on-x64-review). Reserve the active handler before accept. Price a possible torn suffix and its recovery separately from the set of complete durable receipts outstanding for import. If a reply is lost, inspect retained custody evidence before deriving the drain set. No pre-accept marker is proposed.

## Separate general admission from drain

Before each accept, the custodian must establish its local position from validated history, include the worst outcome on either listener and reserve the entire drain. At trip, cease accepting on both public listeners, close queued connections without a WBRS acknowledgment, and finish the one already-admitted handler if any. On restart, recompute before opening either listener. Quiescing a test generator is an operator action; continued connection attempts must still be excluded by the custodian.

Proposed drain interface: operator starts a restricted pair while public listeners stay closed. Give only the isolated recovery worker and custodian access to a private transport. Authenticate the actual connected principals and bind the session to the store, epoch and fixed trip tip. Restrict prepare/confirm to the next verified outstanding receipt's unique import event or its exact replay. Resolve an existing pledge first using the named recovery table. A malformed or out-of-plan maintenance request stops the drain. Reserve its required failure evidence before the session opens. A repeated failed session must not generate another unbudgeted record after restart. Approval requires a concrete access-control and restart protocol that enforces these restrictions, including durable recognition of a terminal drain fault. No general-purpose listener may reopen merely because a process restarted.

## Make history restrictions enforceable

For the first design review, use one enrolled store, epoch 1, one task at most, with both live and already-imported denials allowed. Refuse epoch change before leaving this profile, reserving the administrative refusal. Existing later epochs, invalid history or a mismatched journal enter operator hold. Enrollment and pre-enrollment denial traffic need their own bounded startup path. A fresh empty directory cannot establish a safe post-crash restart on its own.

Freeze limits on total custody bytes and ordinals, event sequence, denial count and maximum frame size. Charge all retained denials to the outstanding-import reserve unless the custodian can verify a tighter bound. Custody pledges alone do not identify event kinds. If a task-count or semantic restriction is necessary to the reserve, supply authenticated evidence that enforces it before admission or use a bound valid for every allowed frame composition. Include partially imported histories, one pending pledge, and possible head republication. A missing pledged event remains operator-only. Reserve for that safe stop without assuming automatic convergence. Unknowns close admission.

## Physical measurement plan (authorization pending)

After the admission definition, private drain, and permitted histories have been reviewed, nominate an envelope for characterization. Declare its maximum history and backlog, byte reservation on a dedicated disposable volume, charged cutoff, deadlines, cgroups and memory arenas. Enumerate the worst reachable states independently of the measured checkpoint fixtures. For each state predict actual examinations and production debits per invocation. Project warning and cutoff in charged units using checked arithmetic and an exact successful-recovery baseline. Show positive notice before cutoff even as denials grow against an unchanged head. Invalid or stale inputs yield CAPACITY_UNKNOWN.

Measure peak allocated blocks of history, head and temporary files, DB, WAL, SHM and indexes through append, sync, checkpoint, drain and recovery. Record available filesystem capacity and enforce exclusive use or a guaranteed allocation for this store. Capture BOOTTIME intervals, arena high-water marks, SQLite heap/cache use and both cgroup memory peaks with swap disabled. Sample before last-client close as well as after. State how unsampled peaks and unrelated disk users are bounded. Check each component against its own ceiling at the same declared envelope.

Require preservation of the exact receipt set, one confirmed binding per outstanding receipt and unchanged already-imported bindings. Acknowledge only durable outcomes. Exercise sustained offered input through halt, storage-sync failure and restart at the observation and drain boundaries. Separate safe refusal under a fault from successful drain with healthy reserved resources. Submit measurements, unresolved cases, warning delivery and the operator's recorded action to Meta before Proto selects close, explicit extension, or hold at Phase 2 exit.
