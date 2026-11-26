# ADR-0009: Controlled local execution of one marker-file action

## Status

**Accepted by Proto on 2026-11-21** for the preproduction x64-review target. Following Phase 2 exit, Proto authorized [Phase 3 entry](../engineering/phase3-entry-review.md) on 2026-11-22 and took ownership of the execution boundary. The first increment covers documentation. The tests below remain implementation proof obligations.

## Context

An operator needs to know whether an approved local action took effect even if its worker crashed or its reply was lost. Phase 2 established how to authorize an attempt and accept evidence. Here the evidence must come from observing an actual filesystem effect. The worker's report cannot establish completion.

The [Phase 2 exit record](../governance/phase2-exit.md) accepts the measured no-op core. WB-EXC-001 expired at Phase 2 exit on 2026-11-22. Further implementation requires a separate owner-approved scope.

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

## Marker event wire profile 1

**Accepted by Proto (Ian), 2026-11-22, following independent specification review by Meta.** Using a separate Python implementation built from ADR-0005 and this profile, Meta reproduced the published proposal and linked approval vectors, including their lengths, the display digest, proposal fingerprint, both heads and approval event digest. The acceptance covers the wire specification. Codec implementation, reader compatibility and live approval enforcement require their own verification. [Entry and implementation scope](../engineering/phase3-entry-review.md)

### Canonical records

Marker events use the ADR-0005 envelope layout with `WBEV` version **2**. Retain its 56-byte header, trailing 32-byte previous head, event digest domain `warband.event.v1\0` and link domain `warband.link.v1\0` (each ends in one zero byte). Apply the ADR-0005 link algorithm. Hash the header and payload exactly as stored, including the version. Integers are unsigned little-endian, concatenated without padding. An ID is a distinct nonzero 16-byte value, a hash is 32 raw bytes and each Ref is the full 32-byte store/epoch/sequence value. Reject overflow, malformed lengths, unknown codes, wrong producer/version and trailing bytes before interpreting an event. [Phase 2 layout and hash domains](0005-event-integrity-acceptance-and-recovery.md#2-canonical-binary-v1)

The table gives payload fields in wire order. Producer version is 1. Producers 1, 2 and 5 keep their normalizer, policy and state-boundary roles. Producer 6 is runtime intake for the authenticated local CLI, 7 is the registered marker observer and 8 is the independent marker evaluator. A producer number alone cannot authenticate a caller.

| Kind / producer | Payload in order | Bytes |
|---|---|---:|
| 11 MarkerProposal / 1 | task ID, run ID, proposal ID, attempt ID, directory ID, directory device u64, directory inode u64, expected task version T u64, expected control revision C u64, policy version u64=2, action u16=2 (create marker), target u8=1 (private attempt directory), criterion u16=2 (approved marker), recovery u8=1 (stop/reconcile), approval required u8=1, payload length N u32, payload[N] | 131 + N |
| 12 MarkerApproval / 6 | proposal Ref, proposal fingerprint F, approved-display length u32, approved-display payload hash, operator UID u64, decision u8 (1 approve, 2 reject), evidence ID | 125 |
| 13 MarkerPermit / 2 | approval Ref, capability ID, expected control revision u64, audit expiry in Unix microseconds u64, use limit u8=1, evidence ID | 81 |
| 14 MarkerClaim / 2 | permit Ref, attempt ID, capability ID, expected task version u64, expected control revision u64, F | 112 |
| 15 MarkerObservation / 7 | claim Ref, evidence ID, delivery u8, worker stopped u8, directory control established u8, entry class u8, observed length u64, observed hash | 92 |
| 16 MarkerEvaluation / 8 | observation Ref, claim Ref, observation event digest, criterion u16=2, verdict u8 (1 verified, 2 incomplete, 3 operator reconciliation), evidence ID | 115 |
| 17 MarkerAccepted / 5 | evaluation Ref, claim Ref, transition ID, expected task version u64, expected control revision u64, new task version u64, state u8=2 (complete) | 105 |

### What the operator approves

The runtime allocates the attempt and directory identities before approval. It provisions the directory under an exclusively controlled parent and records the device and inode from the opened directory. Target 1 resolves only to the fixed ASCII leaf `marker` in that directory. The CLI displays its runtime-owned directory identity and leaf. Caller-supplied paths and shell commands fail normalization. Relocating the attempt or losing continuity of the directory binding requires reconciliation; a reused device/inode pair cannot reestablish exclusive control.

N ranges from 0 through 4,096. The canonical payload is the exact nonsecret byte string to write; preserve every byte, including any final newline. Compute the display digest as SHA-256(payload). Compute F as SHA-256 of the exact ASCII domain `warband.marker.proposal.v1\0` (one final zero byte), followed by the full proposal Ref and the entire kind-11 payload. The Ref binds store and epoch; F also covers the action, target, attempt, versions, policy and payload bytes.

The CLI reads the confirmed proposal, presents its normalized fields, length and full digest, and captures an explicit decision from the authorized local operator. The runtime obtains the UID from the authenticated operator connection. It records the displayed binding for either decision. Record at most one decision per proposal. Rejection ends that proposal. Permit issuance requires one confirmed affirmative decision for this proposal and exact equality of Ref, recomputed F, length and digest with that decision. Missing or rejected approval withholds the grant. A changed proposal requires a fresh Ref and approval; a retry of the same decision can only return its existing fully matching record.

Before claim and immediately before dispatch, resolve the confirmed chain and compare the requested operation and payload with the approved bytes. Recompute F and the payload digest, check current policy and versions at that stage, recheck directory identity/control and require an unused destination before first dispatch. The broker authenticates the request, checks the same target, length and digest, and uses exclusive creation. Record rejection on any mismatch. An existing entry yields occupancy only. The guarantee is **at most one successful creation while the marker remains in place**.

A proposal and its approval leave T/C unchanged. A permit checks T/C and advances control to C+1. A confirmed claim checks T/C+1, consumes the capability once and advances control to C+2. Only its issuing execution can dispatch, with a fresh elapsed-time observation strictly before expiry at claim confirmation and again immediately before dispatch. The elapsed origin starts at authorization construction and stays in private process memory. The recorded expiry is for audit. Dispatch requires the live entry for the same claim, attempt, capability and proposal, and consumes that entry before invocation.

### Observation, verdict and replay

Delivery codes are 1 reply received, 2 reply lost, 3 deadline reached, 4 process failure and 5 unknown. They record the supervisor’s knowledge of delivery. The two evidence flags each accept only 0 (unproven) or 1 (established). A missing proof of worker termination or exclusive directory control requires class 0 (unassessed) and withholds filesystem inspection. With both proofs established, inspect relative to the trusted directory without following links. Record class 1 absent, 2 regular file fully read, 3 nonregular entry, 4 oversized regular file or 5 inspection incomplete.

For class 2, record the exact length (0–4,096) and SHA-256 of all observed bytes after an end-of-file check. An empty file carries SHA-256 of the empty byte string. For class 4, record the observed size above 4,096 and a zero hash. For other classes encode zero length and zero hash. Unknown classes, inconsistent flags and impossible field combinations invalidate the record. Preserve partial and conflicting entries in place.

The evaluator starts from the custody-confirmed observation Ref, recomputes its event digest, resolves the claim through the permit to the exact approval, and compares type, length and digest against that approval. Only class 2 with both proofs and an exact match yields verified, including after a lost reply. Absence yields incomplete. Every other legal outcome requires operator reconciliation. Worker output conveys no verdict. A lost reply, timeout or crash withholds redispatch even when the marker is absent.

Every reference must resolve to its specified earlier role in the same store and epoch. Verify the task/run, proposal, attempt, capability and evidence bindings across the chain. Require one permit per approved proposal, claim per capability/attempt, observation per claim, evaluation per observation and accepted transition per attempt. Acceptance requires a verified verdict, current policy, T/C+2, prior claim consumption, and no revocation or terminal disposition. It requires the fixed complete state and a matching new task version T+1 in the acceptance record. It advances to T+1/C+3 once. Duplicate completion returns the original Ref only on full binding agreement. Replay consumes validated confirmed bytes and rebuilds projections; it never reconstructs live grants or issues a worker request.

### Compatibility and review vectors

Phase 3 readers must retain ADR-0005 v1 decoding and hash its original bytes. In mixed histories, use v1 TaskCreated and the existing rejection, revocation and disposition layouts with role-checked references. Bind v2 marker permits, claims, observations, evaluations and acceptance exclusively to the marker chain. Reject cross-action references in either direction. A Phase 2 reader encountering a v2 event must withhold authoritative projection and protected progress for that history. It must never skip the event, decode it as a NoOp, or rewrite old rows to upgrade a store.

For a reproducible proposal vector, fill the store ID with byte 01 hex and use epoch 1, sequence 2. Fill task, run, proposal, attempt and directory IDs with bytes 02 through 06 respectively (each repeated 16 times). Use device 8, inode 9, T=1, C=0 and payload hex `616263`. The table yields 134 payload bytes, 222 encoded event bytes, display digest `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`, and F `da7e15ffea6ade7f21c3fc1996871787aee98bae7919fe25bf4a9ed7bf3c2f7b`.

For the linked approval vector, use a supplied proposal predecessor of 32 bytes of hex 55 and proposal audit time 10. The resulting proposal head is `102f9fa2a7a24c949afa3babf50320392441b8fd7faa99cd6a5cfec9a57a5851`. At sequence 3 and audit time 11, approve that Ref and F with length 3, the displayed digest, UID 1000 and evidence ID filled with hex 07. The 125-byte approval payload gives event digest `b590294fb37319e3779ae82b0f952d80d4bf34f34a0853b8066fcb5f5e9196b1` and new head `fa52b1686a1a434cee736e1053130cfc041f340cbb03defd3c382b296d746e7a`. These codec vectors use a supplied predecessor; full-history tests must start at an authenticated genesis.

Codec verification must include N=0, 4,096 and 4,097, stale T/C, unknown version/kind/producer, a Ref of the wrong role, and mutation of each approved field against the original approval. Exercise same-length payload substitution, directory substitution, lost reply with exact contents, absent/partial/conflicting files, missing stop/control proof and duplicate acceptance. The real CLI and matching-kernel proof obligations remain in the [verification section](#verification).

### Proposal and approval codec qualification

Proto authorized portable codecs for kinds 11 and 12. The audit suite reproduced the two literal wire events, fingerprint, display digest, approval event digest and both heads. It exercised N=0/4,096/4,097, malformed framing, same-length payload substitution, changes to the scoped Ref, identities, directory, versions and approval binding, and a decodable rejection. The comparison answers whether the affirmative decision binds the supplied proposal. Permit issuance still requires authenticated operator provenance, custody confirmation, current policy and current versions.

On macOS ARM64 and Linux x64 (`x64-review`), the manifest verified 63 tests in seven packages, including all existing v1 vectors. The v1 reducer projected the confirmed TaskCreated control. Appending a valid v2 proposal with a separately computed matching checkpoint yielded IntegrityFault and zero authoritative projection. The reader remains v1-only. Full marker-chain replay and the real CLI tests have separate proof obligations.
