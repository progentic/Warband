# ADR-0009: Controlled local execution of one marker-file action

## Status

**Accepted by Proto on 2026-11-21** for the preproduction x64-review target. Phase 3 entry and implementation require a completed Phase 2 exit record and separate, explicit entry approval from Proto. The tests below remain implementation proof obligations.

## Context

An operator needs to know whether an approved local action took effect even if its worker crashed or its reply was lost. Phase 2 established how to authorize an attempt and accept evidence. Here the evidence must come from observing an actual filesystem effect. The worker's report cannot establish completion.

The Slice 5 capacity checkpoint landed in PR #66. WB-EXC-001 — **Open / Stop at expiry**. Finish Slice 6 and run the successor qualification in parallel. Write the Phase 2 exit record last, with the fault, replay, recovery, operator rehearsal, runner-label and scoped traceability evidence. Phase 3 implementation requires Phase 2 exit and explicit owner entry approval. [ADR-0008](0008-phase2-resource-limits.md#final-disposition-stop-at-expiry-2026-11-21) · [Slice 6 matrix](../verification/phase2-crash-coverage.md)

## Decision

Proto made the following design selections under the [Phase 3 entry plan at c18307c](https://github.com/progentic/Warband/blob/c18307c50ab92d09429090ca183d1e6b365f9ba1/docs/governance/PHASE_PLAN.md#L157-L193).

- [x] Accepted the execution-boundary design during Phase 2.
- [x] Selected Linux x64 on x64-review as **preproduction only**. Record the tested kernel, filesystem, sandbox configuration and source alongside each result.
- [x] Selected exclusive marker creation with the target, approval, observation and recovery contract below.
- [x] Selected the worker limits, enforcement mechanisms and matching-kernel tests below.
- [x] Selected the local CLI approval path. Its positive proof must use the real runtime.

### Marker and approval contract

| Item | Accepted rule |
| --- | --- |
| Action and target | Register one create-marker action. The runtime provisions a private directory for this attempt, establishes its identity and verifies the fixed marker name is absent before dispatch. Keep the directory under exclusive control through observation. The proposal cannot supply a filesystem path or shell command. |
| Payload | Use bounded, nonsecret canonical bytes bound to this proposal. Display the target, byte length and SHA-256 of the entire payload before approval. Apply the payload ceiling in the selected worker profile below. |
| Creation | Exclusively create the regular file at the approved name. An existing entry yields `EEXIST`. The guarantee is **at most one successful creation while the marker remains in place**. Occupancy alone proves neither identity nor contents. |
| Human approval | The local CLI shows the normalized proposal and records the operator decision through the runtime. Bind approval to the full proposal Ref and fingerprint, store/epoch, task/run, action, target, payload and expected versions. Changed bindings require fresh approval. A rejection or missing approval withholds the grant. |
| Worker authority | Authenticate the runtime-to-worker request and the worker identity. Bind the single-use capability to the approved action, target, arguments, policy version, task/run, attempt, expected state and expiry. Consume its use at the confirmed claim. Check the issuing execution's live grant and deadline immediately before dispatch. |
| Evidence and acceptance | After the worker and any writers have stopped, the registered observer opens the entry relative to the trusted directory without following links. Check regular-file type, exact length and complete payload digest against the recorded approval. The evaluator reads the confirmed observation independently. Only the state boundary may accept once for the claim at the expected versions. |
| Recovery and reversibility | A lost reply, timeout or crash records an uncertain outcome. Withhold redispatch. With proven worker stop and exclusive control, an exact match establishes the approved effect occurred. Absence leaves the task incomplete. A partial or conflicting marker is preserved in place for operator reconciliation. If control or worker stop cannot be established, withhold the verdict. An operator may separately authorize removal of a verified marker after evidence is secured and the attempt retired. Record the disposition. |

### Security consequences and matching-kernel tests

The runtime controls directory ownership and worker lifetime. The worker receives only the authority needed to create and write the approved marker. Prevent unlink, rename, replacement and access by other writers. A generic writable directory alone cannot enforce those restrictions. The kernel, runtime, custodian and operator form the trusted boundary. Require an authenticated private control channel, default-deny registration and a worker with no shell interface.

| Control | Required test on the selected Linux kernel |
| --- | --- |
| Network | From inside the worker, attempt an outbound connection and access to a disallowed local endpoint. Verify both are denied with the endpoints reachable from an authorized control process. |
| Filesystem | Create the authorized marker. Attempt an adjacent write, access to the store or custody files, symlink substitution, unlink and rename. Verify denial and compare protected contents before and after. |
| Process | Enforce one worker with no children or shell execution. Exercise child creation and execution of an unregistered program. Verify supervisor accounting and zero surviving writers before observation. |
| Elapsed time | Drive the worker past its approved execution deadline. Verify forced termination of the whole worker scope, an uncertain outcome and withheld redispatch. |
| Memory | Exceed the worker's declared memory ceiling. Record kernel enforcement and verify the runtime retains enough resources to record the disposition. |
| Output | Exceed the declared capture limit and include a recognizable synthetic secret. Verify bounded capture and redaction before persistence, logging, model projection or user display. |

### Selected x64-review worker profile

| Limit | Selected limit | Enforcement |
| --- | --- | --- |
| Canonical payload | 4,096 bytes | Check byte length before approval and again at the authenticated create boundary. Bound the resulting file to the approved length. |
| Elapsed worker time | 5 seconds | Supervisor measures from launch with CLOCK_BOOTTIME, bounded by the remaining enclosing deadline. At expiry terminate the worker scope and verify it is empty before observation. |
| Worker memory | 32 MiB, zero swap | Dedicated cgroup v2 with memory.max and memory.swap.max. The supervisor runs outside it. |
| Worker output | 4,096 bytes combined stdout and stderr per attempt | Supervisor counts both streams against one capture budget, terminates on overflow, and redacts before persistence or display. |

Use an inherited authenticated control channel and a syscall allowlist denying new sockets and connections. Confine the worker to one process with pids.max=1 and deny further execution after worker initialization. A trusted create broker holds the private directory descriptor, resolves only the approved fixed name and performs exclusive creation; the worker receives no writable directory descriptor or general filesystem mutation authority. The harness exercises the same exclusive-create boundary twice for the occupancy test.

During implementation verification, record the effective settings and observed kernel results on x64-review.

## Verification

1. **Real CLI approval.** Approve one normalized proposal from the CLI, then follow its confirmed approval, permit, claim, observation, verdict and single accepted transition. Mutate the payload or a binding after approval and require denial before dispatch. Exercise missing approval, unknown tool, unauthorized target, expiry and missing recovery policy through the execution boundary.
2. **Lost reply after effect.** Suppress the reply after creation. Establish worker termination before opening the marker. Independently compare type, length and full digest to the CLI-approved values. Require one accepted transition on exact match. Repeat with partial and conflicting contents. Require preserved bytes, operator reconciliation, an incomplete task and zero redispatches. Also exercise an absent marker and loss of proof of termination.
3. **Exclusive creation while occupied.** In the harness, keep the first marker in place and exercise the worker's exclusive-create operation a second time at that name. Require `EEXIST` and unchanged file identity and contents. This separate assertion proves the creation bound. The lost-reply recovery path never initiates the second call.
4. **Interrupted and duplicate delivery.** Kill the worker and runtime separately across dispatch and observation. Recover from the confirmed journal. Deliver duplicate dispatch requests and delayed results. Check one consumed claim, at most one accepted transition, preserved unresolved evidence and zero automatic retries.
5. **Security evidence.** Run each sandbox test above with the production worker profile. Record source, target, effective limits, observations, references and dispositions. Cover WB-NEG-002–006, 008, 010 and 011 on the actual path. Harness failure injection supplements the required real CLI proof. [Negative-path catalog](../verification/negative-path-catalog.md)

## Alternatives considered

A successful worker reply is insufficient evidence of filesystem contents. Automatic retry after a lost reply could act on a changed target. Automatic cleanup could destroy the only evidence of a partial write. Independent observation and explicit operator reconciliation preserve that evidence at the cost of withholding completion when the outcome cannot be established.

## Compatibility and migration

Keep Phase 2 NoOp encodings and historical replay stable. Before implementation, specify versioned marker proposal, approval and evidence encodings, identity bindings and fail-closed handling by older readers. Existing NoOp permits and claims confer no marker authority. This decision supersedes no accepted ADR and grants no runtime effect permission.
