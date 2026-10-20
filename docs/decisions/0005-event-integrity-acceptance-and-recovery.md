# ADR-0005 Event integrity acceptance and recovery

- **Status:** Proposed
- **Decision owner:** Proto, project owner (assigned 2026-10-18)
- **Review status:** Amended decision candidate; operator acceptance pending
- **Scope:** Proposed Phase 2 deterministic no-op authority boundary
- **Supersedes:** None
- **Related decisions:** Accepted ADR-0001 through ADR-0003; Proposed ADR-0004
- **Authorization:** Design only. Neither this draft nor Phase 1 acceptance authorizes Phase 2 code.

The owner requested progression to the next phase on 2026-10-18 and assigned Proto as this decision's owner. [Phase 2 entry review](../engineering/phase2-entry-review.md) records the outstanding decisions and proposed review sequence. Owner assignment does not accept this ADR or resolve its implementation gates.

## Context

The foundation has local Linux x64 and macOS ARM64 evidence. It does not yet execute proposals, consume capabilities, verify external observations, commit runtime facts, or replay an authoritative event store.

The next boundary must answer: how can Warband prove that an action used the correct authority, generated trustworthy evidence, and produced at most one valid authoritative transition across failures and restarts?

The constitution remains authoritative. This draft proposes mechanisms beneath it; it does not weaken the contracts or claim unimplemented guarantees.

## Owner-selected storage and custody direction

On 2026-10-18, Proto selected **Option 1: same VM, separate checkpoint custodian**. The selected design direction uses SQLite for the single event store and a separate local custodian process under a distinct OS identity for the trusted checkpoint. The custodian owns its checkpoint storage; the runtime has no direct write access to that storage. Both audit and authoritative projections still derive from the single event history. Checkpoint metadata is not another authoritative event ledger.

The intended protection is detection of alteration, truncation or replacement of checkpoint-covered history by an attacker who can rewrite the journal but cannot control the custodian or its protected storage. The design trusts the VM kernel and administrator. It does not establish detection when an attacker controls both custody domains, compromises guest root, or rolls back the entire VM including the custodian. A separate filename or directory under the runtime's own writable identity does not meet this direction.

Checkpoint custody does not validate the truth of producer observations or authorize state changes. A compromised runtime must not gain an unrestricted checkpoint replacement or reset operation. The protocol direction below uses local peer credentials and a separate operator path; exact wire formats, enrollment and implementation verification remain open. No host-side or remote custodian is selected.

The exact SQLite version, dependency provenance, transaction and synchronization settings, checkpoint persistence mechanism, filesystem assumptions and journal/head crash-state table still require review. This selection is not formal acceptance of ADR-0005, implementation authorization, production architecture selection or verified security evidence.

## Proposed scope and guarantees

Begin with one runtime writer and one deterministic no-op action. Use one durable append-only event history to derive audit and authoritative projections, preserving ADR-0002 and ADR-0003. Derived indexes/caches are reconstructible and never independently authoritative.

The internal acceptance boundary can provide at-most-once committed transitions through atomic expected-version and uniqueness checks. Successful recovery can restore a committed result. Exactly-once external execution is not promised: execution and local persistence cannot generally share an atomic transaction. Unknown side effects remain unknown until independently reconciled. Availability and automatic progress may be sacrificed for safety.

No provider, arbitrary shell, filesystem write tool, broad network adapter, general orchestration, learned promotion, or distributed consensus is introduced by this proposal. Linux worker isolation and future tool contracts need their own review before powerful tools are added. A no-op test is not sandbox proof.

## Proposed canonical event envelope

Use a versioned deterministic binary encoding with a distinct runtime format, not the 25-byte Phase 1 fixture. The amendment below specifies the v1 widths/order and kind-specific payload registry for operator review before implementation.

Proposed envelope fields, in this order:

| Field | Representation and rule |
|---|---|
| Format marker and schema | Fixed runtime marker and explicit schema version; unknown versions rejected |
| Store identity | Fixed-width identity separating histories and identifier namespaces |
| Custody epoch | Explicit epoch identity binding this history segment to its checkpoint authority; stale-epoch requests rejected |
| Audit sequence | Unsigned fixed-width integer; strict monotonic order, no reuse/wrap |
| Event identity | Full `(store, epoch, sequence)` tuple, represented as a distinct domain type |
| Kind | Registered enum with a schema-defined payload; unknown kind rejected |
| Recorded timestamp | Fixed-width integer under an explicitly defined epoch/unit; no native struct layout |
| Task/run/proposal/attempt references | Distinct identifiers with explicit presence encoding and required bindings per kind |
| Producer identity and version | Registered runtime producer, not supplied as authority by the model |
| Payload length and bytes | Bounded, schema-specific canonical encoding; no generic arbitrary map order |
| Previous event hash | Fixed-width hash linking the immediately preceding event |

The proposed link calculation has two domain-separated stages: an event digest over the canonical envelope fields other than the previous-head field, followed by a head hash binding that digest to the custody epoch, store identity, sequence and previous head. The previous head is bound by the link stage, not silently omitted from integrity coverage. The custodian independently recomputes the link from supplied digest and binding fields. The runtime verifies the supplied digest against the exact persisted canonical event. Exact encodings, domain separators and independent vectors are specified in the amendment below. The runtime supplies ordering, identities and producer metadata; a model-supplied hash or verification flag is never authority. Custodian link checking detects inconsistent calculations, not fabricated content from a compromised authorized runtime.

The amendment selects fixed-width little-endian integers, bounded exact UTF-8 without normalization, SHA-256 and explicit v1 payloads; these are candidate decisions awaiting operator acceptance. Reject malformed, ambiguous, duplicate-field, oversized, unknown, or noncanonical representations. A payload codec registry and independent golden vectors are acceptance prerequisites; no implementation may guess omitted fields.

Proposal fingerprints use a separate domain/schema from event hashes. Bind the normalized tool, arguments, target, expected effect, task/run, policy version, approval requirements, and recovery disposition. The runtime owns allowed effect criteria; a proposal cannot weaken its own success test.

## Integrity and trusted heads

A hash chain alone cannot detect deletion of a valid suffix or a complete rewrite when the attacker also supplies the expected head. Verification needs an independently trusted store identity, sequence, and hash checkpoint covering the history being trusted.

Under the owner-selected direction above, the protected-head interface belongs to the separate same-VM custodian. Its access controls and advancement protocol keep custody outside the defined journal-rewrite attacker's control under the stated assumptions. Checkpoints and their attestation history are integrity metadata, not a second event ledger. No automatic remote anchoring service is authorized.

The trusted head covers every security event acknowledged as durable before dispatch or publication. The selected protocol direction is pledge before SQLite commit, then confirm before acknowledgment. A valid chain with no custodian pledge does not establish tail provenance and is never automatically re-attested. If local commit succeeds but confirmation is uncertain, withhold dispatch/publication and follow the recovery table. Do not report that committed bytes were rolled back.

On 2026-10-18 the owner directed preparation of this revised prepare/confirm design and selected operator reconciliation, with no automatic cancellation, for a durable pledge without its SQLite event. The following is a review specification, not implemented or fault-tested behavior. The event-integrity contract's four viewpoints must be aligned before acceptance. No guarantee against an attacker controlling both journal and checkpoint custody is claimed.

### Custodian operations and identities

Use per-event attestation and at most one outstanding PENDING pledge per store. Each normal operation binds the epoch, store identity, predecessor sequence/head, new sequence/head and event digest. Require exactly the next sequence for this per-event profile; overflow fails closed. Compare and append are serialized within the custodian.

| Operation | Required behavior |
|---|---|
| `prepare` | Authenticate the runtime; match the current epoch/store and committed predecessor; recompute the proposed link; durably append PENDING before replying. An exact replay of the outstanding pledge returns its existing receipt. A different request cannot replace a pending pledge. |
| `confirm` | Authenticate the runtime and match the entire pending tuple. Append and fsync COMMITTED, publish the head durably, then return success. An exact replay of the latest committed tuple returns its original success only after head publication/recovery is complete; it creates no new record. Other predecessor or tuple mismatches never overwrite state. |
| `verify` | Return the epoch, store identity, committed sequence/head, any pending tuple and current fault/readiness state from validated custodian metadata. A committed history record awaiting head publication is not reported as ready. |
| `epoch_change` | Authenticate a separately authorized local operator; bind the exact old epoch/head, proposed new epoch/sequence/head, reason and authorization identity. Preserve the old history and any unresolved pledge. No runtime-accessible reset or automatic cancellation exists. The amendment specifies candidate transition and enrollment formats for owner review. |

The old single-step `advance` operation is replaced by prepare/confirm; retaining a bypass would defeat the pledge. Lost prepare and confirm replies are handled by exact replay. Arbitrary older requests, stale epochs and changed tuples are rejected, not treated as idempotent success.

Linux uses connected Unix stream sockets with `SO_PEERCRED`. Authenticate the runtime UID against an explicit allowlist and have the runtime verify the custodian identity. Use a distinct administrative endpoint with an operator UID allowlist excluding the runtime UID. Root is trusted under Option 1. The operation model is transport-independent, but this authentication profile is local-socket-specific; peer identity does not prove executable integrity or honest observations.

Custodian storage is owned by its separate identity and inaccessible to runtime writes. The socket path and storage paths need protected parents, reviewed ownership/modes/ACLs, no untrusted group-writable parents, and no path substitution through symlinks. Required future verification includes actual denied access under the runtime identity, not metadata inspection alone. No such permission evidence exists yet.

### Durable custody records and publication

The append-only custodian history is the recovery source for checkpoint metadata; the current head file is its materialized committed head. Each bounded frame includes its type, epoch/store, full request tuple, previous custody-record hash, length and checksum. PENDING and COMMITTED frames are distinct. Epoch transitions retain their authorization metadata. Hash chaining detects mid-file edits relative to retained trusted records; it does not survive an attacker controlling custodian storage.

For prepare, append the complete PENDING frame and fsync history before replying. For confirm, append the corresponding COMMITTED frame and fsync history first. Then create a new head file exclusively inside the custodian directory, write it completely, fsync it, rename it over the old head on the same filesystem and fsync the directory. Return success only after all required steps complete. Initial creation also requires durable directory entries. Check every write, short write and synchronization result. Head rename and history append are not one atomic transaction.

On restart, a structurally truncated final frame alone may be removed back to the last complete valid frame, durably, before new writes. Never remove a complete frame with a bad checksum or chain link, an earlier damaged record, or a truncated suffix needed to explain the published head. Those are attestation-history faults. Recover a stale head from complete valid COMMITTED custody records only; never regenerate custody history from SQLite. An unmatched final PENDING remains a live pledge after repair. The amendment defines the candidate frame layout and hash inputs.

### Writer ordering and visibility

The single-writer lock spans preparation, SQLite commit, confirmation and the acknowledgment/dispatch gate. On process death the OS lock is released; the next writer reacquires it and reconstructs the unresolved-work gate from custodian metadata and SQLite before admitting work. A custodian-side pending check also rejects competing pledges. No in-memory flag alone establishes recovery state.

1. Construct the exact canonical event and its bound digest/head from supplied decisions.
2. Durably prepare its pledge with the custodian.
3. Revalidate transaction preconditions and commit that exact event to SQLite. A failed commit leaves its pledge unresolved; it does not silently release the gate.
4. Read/validate the committed event against the pledge and confirm with the custodian.
5. After durable confirmation, apply the acknowledgment/dispatch gate before releasing the writer lock or admitting another mutation.

Reads expose only checkpoint-confirmed authoritative projections. Diagnostic reads may label pending records explicitly, but cannot present committed-but-unconfirmed events as completion. Normal reads must also respect an active integrity fault. A durable dispatch claim is permission to attempt execution, not evidence it occurred: recovery of a confirmed claim alone never automatically redispatches uncertain work.

The proposed Linux SQLite profile is WAL with `synchronous=FULL`, explicitly set and queried on every writing connection. Exact SQLite pin, local filesystem/VFS and VM disk flush assumptions remain review inputs. SQLite durability and custody durability are distinct requirements. macOS development, including any `fullfsync` and `checkpoint_fullfsync` settings, carries no power-loss durability claim; Linux evidence cannot be inferred from a native macOS pass.

### Crash and integrity recovery table

Automatic means only the specified metadata reconciliation or exact confirmation; it does not authorize execution, retry, completion or policy reinterpretation. Validate store identity/epoch and the checkpoint-covered event prefix before applying any row. Multiple faults retain all applicable diagnostics; an identity/integrity fault overrides a more permissive recovery row.

| Crash point or observation | Named state | Recovery | Required disposition |
|---|---|---|---|
| Before any durable PENDING; SQLite equals confirmed head | `READY` | Automatic | No new event was authorized by custody; admit work through normal gates. |
| After durable prepare, before SQLite commit; pending event absent | `PENDING_EVENT_MISSING` | Operator-only | Preserve pledge and stop new work. Owner selected no automatic cancellation. |
| After SQLite commit, before confirm; exact pending event present | `PENDING_CONFIRMATION` | Automatic | Recompute event digest/link from SQLite; match the full pledge, sequence and prefix; resume exact confirm. Withhold acknowledgment/dispatch until ready. |
| After complete durable COMMITTED append, before head publication | `HEAD_PUBLICATION_PENDING` | Automatic | Custodian publishes the head from its validated history, then runtime verifies SQLite matches. No success before publication. |
| After head rename but before directory fsync or confirm reply | `ATTESTATION_UNCERTAIN` | Automatic if records validate | Custodian validates history/head and completes durable publication; exact confirm replay returns its original receipt. Otherwise use the applicable fault below. |
| After durable head publication, before acknowledgment | `CONFIRMED_RESPONSE_PENDING` | Automatic | Return the recorded result after comparison, without adding a fact. A confirmed dispatch claim alone does not prove whether dispatch already happened. |
| Only a truncated final custody frame; remaining history explains head | `TORN_FINAL_RECORD` | Automatic | Remove only the incomplete final frame durably, recover the resulting READY/PENDING/COMMITTED state and apply its row. |
| SQLite ahead with no exact pledge, including an extra suffix beyond it | `UNATTESTED_TAIL` | Operator-only | Preserve evidence; no chain-only re-attestation, truncation or automatic repair. |
| SQLite behind confirmed history, checkpoint hash differs, or pending event differs | `INTEGRITY_FAULT` | Operator-only | Block mutation/dispatch/trusted completion; investigate. Epoch change requires separate operator authorization. |
| Custody history valid but head malformed, stale or missing with a recorded genesis | `CHECKPOINT_INCONSISTENT` | Automatic only if uniquely reconstructible | Rebuild head from custody history; do not reconstruct history from the event store. A contradictory valid head is an integrity fault. |
| Complete bad frame, broken custody hash link, interior corruption or unexplained published head | `ATTESTATION_HISTORY_FAULT` | Operator-only | Preserve damaged files; no speculative history repair or reset. |
| Store exists without trusted custody history/checkpoint and no authorized genesis | `CHECKPOINT_MISSING` | Operator-only | No automatic enrollment from existing SQLite contents. |
| Store identity differs or epoch is unsupported/stale | `STORE_IDENTITY_MISMATCH` / `EPOCH_MISMATCH` | Operator-only for persisted mismatch | Reject requests without mutation; investigate persisted disagreement. Do not relabel a store. |
| Custodian unreachable or request outcome unknown | `ATTESTATION_UNCERTAIN` | Automatic exact replay after recovery | Block protected progress; no timeout-based assumption that a write failed. |
| Disk full, write error or fsync failure | `CHECKPOINT_STORAGE_FAULT` | Operator-only before resumption | No success; preserve current files and pending state. Restore storage health, then reconcile actual records. |
| Peer outside the operation's UID allowlist | `CUSTODIAN_AUTH_FAULT` | Terminal for request | Reject without mutation; no fallback authentication. |
| Different predecessor/request conflicts with committed or pending tuple | `CHECKPOINT_CONFLICT` | Terminal for request; operator review if persisted divergence | No overwrite. Exact latest committed replay is the narrowly defined exception, not a conflict. |
| Unsafe custody ownership, permissions, ACLs or parent path | `CUSTODY_BOUNDARY_FAULT` | Operator-only | Refuse startup or further protected operations until boundary is restored and reviewed. |

An operator recovery action records a disposition; it is not evidence that missing work succeeded. No epoch change suppresses the original fault or creates an authoritative completion. Operator acceptance of the amendment remains required before implementation.

## Authority and evidence

Every authoritative transition kind, including control-state changes, needs recorded runtime-produced evidence and a producing event. The state boundary is the only writer; coordinator, model, tool, and evaluator outputs remain inputs.

Before execution, bind authorization to normalized proposal digest, exact action/target, task/run, attempt, policy epoch, expected task version, required approval, lease expiry/use limit, and predefined recovery disposition. Approval-required actions remain rejected until approval provenance/binding is implemented.

Capability issuance and consumption use the runtime registry. Caller-provided IDs alone cannot grant authority. Persist one consumption claim per lease/use and one dispatch attempt per claim. Verify approval/policy freshness, current state, expiry, revocation, and all bindings at claim time. Reject wrong scope, replay, or changed payload.

A trusted observer records bounded outcomes against the persisted attempt identity. An independent evaluator checks runtime-owned criteria and references registered producer identity, observation digest, covered criteria, and producing events. Executor/model assertions of success do not substitute for an observation. Reject evidence from another task/run/attempt, substituted content, unknown producers, or missing criteria. Secret-bearing data requires a reviewed redaction/evidence policy before a tool exposing it is added.

## Proposed transaction boundaries

All persisted control and task state is derived from the same event history. Distinguish audit sequence, task state version, capability consumption identity, attempt identity, and transition identity; they are not interchangeable counters.

| Boundary | Atomic local work | Gate after durable recording |
|---|---|---|
| Authorization | Append proposal normalization result, explicit policy/recovery decision, required approval binding and capability grant evidence | No dispatch from an unrecorded or untrusted authorization |
| Dispatch claim | Validate expected state/policy/approval/lease; atomically consume permitted use and append one attempt claim with authorization receipt | Dispatch only after the claim is durable and covered by the trusted head |
| Observation | Append trusted observer result or explicit unknown-outcome record, bound to the attempt | Evaluation only uses recorded observations |
| Evaluation | Append evaluator identity/result/coverage and evidence references | Evaluation alone cannot mutate task state |
| Acceptance | Revalidate bindings/current task version/evidence; append one accepted transition fact under unique transition/attempt constraints | Publish authoritative completion only through the state boundary and required integrity gate |

The storage adapter executes transactions requested by the domain plan; it does not invent policy. Expected-version and unique-identity checks must be in the same local transaction as acceptance. Concurrent acceptors cannot both commit against the same eligible version. If a duplicate already committed, return its recorded result without creating a new fact or re-executing the action.

Separate task and control-state version rules must define which claim/authorization events advance each projection. A result must target the version owned by its persisted claim, not an accidentally stale pre-claim version. Task creation, grant, consumption, completion, and recovery require an explicit transition/evidence registry before coding. There is no direct fact-insertion API.

SQLite is the owner-selected direction for the first local transactional store. Its exact dependency profile, durability, constraints, locking, checkpoint integration, migrations and power-loss assumptions require review before implementation. Do not add a second authoritative database or rewrite prior accepted ADRs to justify storage shortcuts.

## Recovery dispositions

| Last proven boundary | Required behavior |
|---|---|
| No durable dispatch claim | No action permitted; reevaluate only through the normal authorization gate |
| Durable claim, no proven outcome | Mark indeterminate; do not automatically redispatch the consumed lease |
| Proven observation, no evaluation | Reevaluate recorded evidence deterministically; do not rerun the tool |
| Proven evaluation, no acceptance | Revalidate the current version and attempt bindings; commit once or record rejection |
| Accepted fact, caller missed response | Return the stored result; no second transition or execution |
| Integrity or storage failure | Stop mutation/dispatch/publication; surface the failure and reconcile before trusting replay |

Retry requires recorded evidence proving it is safe plus a new allowed attempt/lease. A timeout, lost worker response, or crash is not proof no side effect occurred. Recovery dispositions are typed: reconcile, compensate, request approval, or reject/stop. Compensation is a separately authorized and verified action; it may not erase residual effects. Never call uncertain work complete.

## Deterministic replay

Replay validates schema, ordering, hashes, trusted head, identifier uniqueness and reference closure before constructing authoritative state. Apply only eligible accepted facts through pure transition rules; raw claims, failed attempts and rejected results remain audit-only for task completion.

Replay performs no model call, tool execution, capability reissue, retry, compensation, live clock lookup, or reinterpretation under today's policy. Recorded identities, versions, policy/evaluator decisions and criteria form the historical input. A schema migration needs a reviewed explicit procedure; unsupported history blocks trust instead of being silently skipped.

## Proposed verification matrix

These are required future proofs, not passing Phase 1 tests.

| Concern | Required proof | Existing requirements |
|---|---|---|
| Authority and proposal isolation | Direct/forged fact insertion rejected; parser/model paths cannot access state writer | WB-CON-001/002; WB-INV-001/009 |
| Canonical encoding | Independent cross-platform golden vectors, hash vectors, malformed/unknown/ambiguous input rejection | WB-CON-007/008; WB-NEG-001/012 |
| Capability/approval | Scope, expiry, revocation, reuse, policy/state drift and payload mutation rejected | WB-CON-004/005/009; WB-INV-002/003/004/007; WB-NEG-003/004/008/010 |
| Evidence provenance | Fabricated success, unknown producer, substituted/cross-run evidence and incomplete criteria rejected | WB-CON-003/006; WB-INV-005/009; WB-NEG-007 |
| Atomic acceptance | Duplicate/stale/out-of-order delivery and concurrent acceptors cannot create another valid fact | WB-CON-006/008; WB-INV-008; WB-NEG-005/006 |
| Audit/integrity | Alteration, reorder, truncation, rollback, whole-history replacement and head conflict detected within reviewed assumptions | WB-CON-007/008; WB-INV-006; WB-NEG-009 |
| Crash recovery | Inject failure before/after each durable boundary; never redispatch uncertain execution or acknowledge unproven completion | WB-CON-006/008/009; WB-INV-004/005/008 |
| Replay | Mixed accepted/rejected history produces identical state without I/O or live-policy/time reinterpretation | WB-CON-001/006/008; WB-INV-009 |

Learning/promotion remains unsupported under WB-INV-010. Provider independence WB-CON-010 is preserved by deterministic/adversarial proposal fixtures, not a real provider integration.

## Compatibility migration and review gates

There is no runtime event history to migrate. Preserve the Phase 1 fixture format and its tests as independent foundation data; do not reinterpret its bytes as events. A runtime format receives its own schema and domain identifiers.

Before acceptance, freeze the complete wire/payload and transition registries; complete review of storage durability and the selected same-VM checkpoint custody; resolve journal/head crash windows and task/control version rules; define the observer/evaluator trust boundary; and reconcile procedure-layering/effect dispatch without placing I/O in pure domain rules. Proto is assigned as decision owner. High orchestration, pure decisions and technical adapters must be reviewed against repository guidance; no exception is silently accepted here.

On acceptance, align authoritative-state, model-proposal, independent-evaluation and event-integrity contracts, security/trust/threat documents, execution pipeline, package/dependency ownership, negative paths and traceability. Preserve existing identifiers; add new cases for newly specified failures. Authorize Phase 2 implementation separately, beginning with the deterministic no-op and the required rejection/crash/replay proofs.


## Amendment: resolved Phase 2 decision candidate

This amendment is a design specification, not implementation or ADR acceptance. The operator requested these decisions and separate review PRs. Existing unresolved fields are visible in the [reviewed baseline, lines 39–63](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/decisions/0005-event-integrity-acceptance-and-recovery.md#L39-L63); the fixed custody direction and fault dispositions are retained above. The Phase 2 entry requirements remain in [the phase plan, lines 100–107](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/governance/PHASE_PLAN.md#L100-L107).

### 1. Event identity

**Decision:** Event identity and every event reference are `(store_id, epoch, sequence)`. Store IDs are 16 opaque bytes, epochs and sequences are unsigned 64-bit integers. Store IDs are nonzero; epochs start at 1, ordinary event sequences at 1. Sequence 0 is the epoch's custody genesis, not an event. Epoch increases exactly by one under operator authorization; sequence may restart at 1 in that new epoch. Overflow is a fault, never wraparound.

Every event primary key, foreign reference, replay index and uniqueness constraint includes all three fields. Task, run, proposal, capability, attempt, evidence, transition, command and authorization IDs are distinct nonzero 16-byte types, scoped to store and epoch; their lookup keys include that scope. An event reference never resolves in an implicit current store/epoch. Cross-epoch task/evidence references are rejected in v1.

**Alternative:** Keep `(store, sequence)` and forbid sequence reuse forever. **Consequence:** Including epoch preserves the selected epoch recovery mechanism without identity collisions; references occupy 32 bytes and require explicit scope checks.

### 2. Canonical binary v1

**Decision:** All integers are unsigned little-endian, with exact widths below. No native struct layout, padding, floats, varints, maps, duplicate fields or trailing bytes. Text is exact well-formed UTF-8 without normalization or NUL, encoded as `u16 byte_count || bytes`, maximum 1024 bytes. Missing text is length zero only when the schema explicitly permits it. Hashes are 32 raw bytes. `Ref` is `store[16] || epoch:u64 || sequence:u64`; `OptionalRef` is tag `u8` (0 absent, 1 followed by Ref); any other tag is invalid. Absent IDs in conditional payload fields are exactly 16 zero bytes; zero is otherwise invalid. Unknown schema, kind, producer, enum or reserved flag fails closed.

| Event body field, in order | Bytes / rule |
|---|---|
| Magic / version / kind | ASCII `WBEV`, u16=1, u16 from registry below |
| Store / epoch / sequence | 16 / u64 / u64; the full event identity |
| Recorded time | u64 microseconds since 1970-01-01T00:00:00Z; runtime observation, never a replay clock |
| Producer / producer version | u16 / u16, exact registry below; version=1 |
| Payload length / payload | u32 / exact kind schema; maximum payload 65536 bytes |

The body header is 56 bytes. An encoded event is `body || previous_head[32]`; total maximum 65624 bytes. All payload schemas concatenate their fields in listed order. No optional references exist except where explicitly stated.

| Kind / producer | Exact payload fields in order |
|---|---|
| 1 TaskCreated / 1 | task ID, run ID, command ID, input SHA-256, inline evidence ID |
| 2 ProposalRecorded / 1 | task ID, run ID, proposal ID, expected task version:u64, policy version:u64, action:u16=1 (NoOp), target:u8=0 (none), argument length:u32=0, criterion:u16=1 (NoOpV1), recovery:u8=1 (stop/reconcile), approval required:u8 (0/1) |
| 3 AuthorizationRecorded / 2 | proposal Ref, expected control revision:u64, decision:u8 (1 permit/2 reject/3 require approval), capability ID, expiry microseconds:u64, use limit:u8, inline evidence ID |
| 4 DispatchClaimed / 2 | authorization Ref, attempt ID, capability ID, expected task version:u64, expected control revision:u64, proposal fingerprint[32], claim time microseconds:u64 |
| 5 ObservationRecorded / 3 | claim Ref, evidence ID, outcome:u8 (1 returned/2 indeterminate), criterion:u16=1, observed bytes[4] (ASCII `NOOP` for returned; four zero bytes for indeterminate) |
| 6 EvaluationRecorded / 4 | observation Ref, claim Ref, observed-event digest[32], criterion:u16=1, verdict:u8 (1 verified/2 rejected), evidence ID |
| 7 TransitionAccepted / 5 | evaluation Ref, claim Ref, transition ID, expected task version:u64, expected control revision:u64, new task version:u64, new state:u8=2 (complete) |
| 8 RejectionRecorded / 1–5 | stage:u8 (1 input/2 authorization/3 claim/4 observation/5 evaluation/6 acceptance/7 recovery), reason:u16 from reason registry, related OptionalRef, rejected-input SHA-256 |
| 9 CapabilityRevoked / 2 | authorization Ref, capability ID, expected control revision:u64, reason:u16 |
| 10 AttemptDisposition / 5 | claim Ref, expected control revision:u64, disposition:u8 (1 indeterminate/2 reject-stop), reason:u16 |

Reason registry: 1 malformed, 2 unsupported, 3 identity mismatch, 4 stale version, 5 expired, 6 revoked, 7 already used, 8 approval unavailable, 9 evidence invalid, 10 outcome uncertain, 11 missing recovery policy, 12 operator revocation. The stage must match the emitting producer's role; arbitrary producer/stage combinations are invalid. Input rejection containing no usable IDs still has its own runtime-owned event identity and input digest; raw rejected input is not persisted. For authorization decision 1, capability ID is nonzero, use limit=1 and expiry must exceed recorded authorization time. Decisions 2/3 use zero capability/expiry/use limit and grant nothing. No approval-required proposal can receive permit in Phase 2; the approval-binding positive path belongs to Phase 3. This is a scoped rejection proof, not a claim of a working human approval flow.

Hash domains below are their exact ASCII bytes including the final zero byte; concatenation is byte concatenation:

- `event_digest = SHA256("warband.event.v1\0" || body)`.
- `new_head = SHA256("warband.link.v1\0" || store[16] || epoch:u64 || sequence:u64 || previous_head[32] || event_digest[32])`.
- `proposal_fingerprint = SHA256("warband.proposal.v1\0" || canonical ProposalRecorded payload)`. The payload binds task/run, expected state, exact no-op shape, policy, criterion, recovery and approval requirement. No proposal-selected criterion weakens NoOpV1.
- `request_digest = SHA256("warband.request.v1\0" || complete request bytes)`.

#### Custody frames, head and request framing

Custody history uses a separate ordinal:u64 starting at 1 and never resetting across epochs. Each frame starts with `WBCH || version:u16=1 || type:u8 || payload_length:u32 || ordinal:u64 || previous_record_hash[32]` (51 bytes), followed by `header_hash[32]`, payload, then `record_hash[32]`. Types are 1 PENDING, 2 COMMITTED, 3 GENESIS, 4 EPOCH. Maximum payload is 65536 bytes; maximum frame is 65651 bytes. First previous-record hash is zero. Header hash is SHA256 of `"warband.custody.header.v1\0" || first 51 bytes`; record hash is SHA256 of `"warband.custody.record.v1\0" || header including header_hash || payload`. The record hash is also the frame checksum and receipt. A bad complete header/hash/link is corruption, never a truncation repair. A final incomplete header is repairable only if all present fixed fields are consistent; an invalid prefix is a fault. A valid complete header with insufficient final payload/checksum is a truncated final frame, subject to the recovery table's head-consistency rule. No scan-forward resynchronization is allowed.

PENDING/COMMITTED payload is the exact 136-byte tuple: `store[16], epoch:u64, prev_seq:u64, prev_head[32], new_seq:u64, new_head[32], event_digest[32]`. COMMITTED must match the outstanding PENDING, including its epoch. Exact replay returns the original record-hash receipt. A later pending pledge does not invalidate the latest committed request's replay receipt or allow that replay to clear the later pledge.

GENESIS payload is the enrollment payload defined below. EPOCH payload is the epoch-change payload below. A materialized head is `WBHD || version:u16=1 || committed Ref || head[32] || committed_record_hash[32] || checksum[32]`; checksum is SHA256 of `"warband.head.v1\0" || all preceding head-file bytes`. Size is 134 bytes. The GENESIS/EPOCH record supplies sequence 0 until the first event is confirmed.

A socket request is `WBCR || version:u16=1 || operation:u8 || payload_length:u32 || payload`, maximum payload 65536. Operations: 1 prepare and 2 confirm carry the tuple; 3 verify carries store[16]/epoch:u64; 4 enroll and 5 epoch_change are administrative only and carry the payloads below. Requests are length-delimited; EOF, excess bytes, unsupported versions and unknown operations reject without mutation. An application reply is `WBRS || version:u16=1 || operation:u8 || status:u16 || payload_length:u32 || payload`. Its fixed payload is request digest[32], receipt[32] (zero on rejection), committed Ref, head[32], pending tag:u8 (0/1), followed by the pending tuple only for tag 1. Replies never contain raw prompts, paths, credentials or generic error text.

Status registry is 0 READY; 1 PENDING_EVENT_MISSING; 2 PENDING_CONFIRMATION; 3 HEAD_PUBLICATION_PENDING; 4 ATTESTATION_UNCERTAIN; 5 CONFIRMED_RESPONSE_PENDING; 6 TORN_FINAL_RECORD; 7 UNATTESTED_TAIL; 8 INTEGRITY_FAULT; 9 CHECKPOINT_INCONSISTENT; 10 ATTESTATION_HISTORY_FAULT; 11 CHECKPOINT_MISSING; 12 STORE_IDENTITY_MISMATCH; 13 EPOCH_MISMATCH; 14 CHECKPOINT_STORAGE_FAULT; 15 CUSTODIAN_AUTH_FAULT; 16 CHECKPOINT_CONFLICT; 17 CUSTODY_BOUNDARY_FAULT; 18 MALFORMED; 19 UNSUPPORTED. A successful prepare/confirm returns READY for that operation, but prepare does not advance the committed head or clear the runtime pending-work gate. For an unestablished committed head, Ref/head are all zero and only fault/admin replies are valid. Permission is determined by authenticated endpoint identity, never operation bytes alone.

**Migration:** v1 rejects unknown versions rather than attempting another parser. No in-place rewrite of events or custody history. A later migration needs a new reviewed schema/ADR, a verified source snapshot and explicit operator authorization, retaining original bytes and full event identities. Phase 1's fixture stays unchanged. [Golden vectors](../verification/adr0005-golden-vectors.json) are specification data, not a runtime codec or passing runtime test.

**Alternative:** Generic maps/canonical JSON and extensible payloads. **Consequence:** Fixed binary schemas reduce interpretation choices but make changes explicit migrations. Numeric limits are v1 bounds, not performance claims.

### 3. Enrollment and epoch transitions

**Decision:** Enrollment is an out-of-band operator action against an empty event store with no prior custody enrollment. Its payload is `store[16] || epoch:u64=1 || authorization_id[16] || reason:text`; reason is nonempty. Genesis head is SHA256 of `"warband.genesis.v1\0" || enrollment payload`. Runtime credentials cannot enroll, replace a missing checkpoint or manufacture an operator authorization. The custodian records the authenticated operator UID and complete authorization payload in a durable administrative receipt; UID is u64 in the GENESIS/EPOCH history payload suffix. The genesis head hashes only the enrollment payload before that UID suffix. The operator UID is custody evidence, not an untrusted request field.

Epoch-change request payload is `old Ref || old_head[32] || new_epoch:u64 || new_seq:u64=0 || new_head[32] || authorization_id[16] || reason:text || unresolved_pending_record_hash[32]` (zero only if none). New epoch is exactly old epoch+1. New head must equal SHA256 of `"warband.epoch.v1\0" || old Ref || old_head || new_epoch:u64 || authorization_id || reason:text || unresolved_pending_record_hash`). Custodian history appends the request payload plus the authenticated UID:u64. Authorization IDs are unique for the store's complete custody history; exact replay of the latest successful administrative request returns its receipt, changed/reused authorization rejects. Preserve the previous epoch and pledge; do not append an automatic cancellation.

Operator quiesces both writers, preserves the old SQLite files/WAL and custody metadata, and starts an empty new epoch segment after investigation. No tasks, capabilities or accepted facts are silently carried from an untrusted segment. Epoch administration may remain interrupted/faulted until the operator completes installation and comparison; there is no automatic cross-store administrative transaction or runtime repair. A corrupt custody history cannot supply a trustworthy old head: stop for investigation, rather than allow epoch_change to invent one. Operator recovery does not declare missing work complete.

**Alternative:** Automatically enroll or reset from SQLite contents. **Consequence:** Rejected: it would let the rewriteable store establish its own trust anchor. Manual work is an accepted availability cost.

### 4. Versions and acceptance table

**Decision:** Task version starts at 1 with TaskCreated and advances only on TransitionAccepted. Control revision is per task/run, starts at 0, and advances on grant, consumption, revocation, accepted transition or an attempt disposition. Attempt identity is immutable, distinct from both counters. All task/control/attempt lookups are scoped by store and epoch. A SQL acceptance transaction checks expected task/control values, current grant/consumption/revocation state, reference closure and uniqueness, and appends the event plus derived indexes atomically. Indexes are reconstructible; they are not a second authoritative ledger. Reads expose only the custodian-confirmed prefix.

| Event | Preconditions | Task/control change | Evidence | Unique key in addition to full event Ref |
|---|---|---|---|---|
| TaskCreated | New nonzero task/run/command; registered input producer | task=1, control=0 | Inline evidence ID + SHA256 of `"warband.task.v1\0" || task ID || run ID || command ID`; producing event is this event | task/run and command |
| ProposalRecorded | Existing incomplete task/run; matching expected version; exact NoOp shape | None | Canonical input and derived proposal fingerprint | proposal ID |
| AuthorizationRecorded permit | Current proposal/policy; recovery=stop; no approval required; matching control; unused capability ID | control+1 | Producer-2 deterministic decision over recorded proposal; inline evidence ID, producing event is this event | capability ID and proposal authorization |
| AuthorizationRecorded reject/require approval | Recorded proposal; no capability grant | None | Recorded decision and proposal reference | event Ref |
| DispatchClaimed | Permit; current task/control/policy; runtime claim time before expiry; not revoked/used; all proposal bindings match | control+1, consume one use | Authorization event and runtime-generated claim binding | capability use and attempt ID |
| ObservationRecorded | Existing confirmed claim; registered observer; matching attempt; one observation | None | Exact bounded observed bytes or explicit indeterminate outcome | attempt observation and evidence ID |
| EvaluationRecorded | Existing confirmed observation; registered evaluator; recomputed observation digest; same claim/criterion | None | Observation Ref/digest and evaluator verdict | observation evaluation and evidence ID |
| TransitionAccepted | Verified NoOpV1 evaluation; same claim; matching task/control; capability consumed by that claim and not revoked; current recorded policy version | task+1, control+1 | Evaluation -> observation -> claim -> authorization -> proposal chain | transition ID and accepted attempt |
| RejectionRecorded | Known stage/reason; registered producer; valid optional reference | None | Rejected-input digest; no raw secret-bearing input | event Ref |
| CapabilityRevoked | Existing grant, matching capability and control; not already revoked | control+1 | Registered policy producer's recorded operator/policy revocation reason | capability revocation |
| AttemptDisposition | Existing claim; matching control; no accepted transition | control+1 | Producing claim plus recorded recovery reason | attempt terminal disposition |

All uniqueness keys above include store/epoch. The same permit is not reissued as another grant after a claim. A recovery retry needs a newly authorized proposal/attempt after operator reconciliation, not resurrection of a consumed lease. Completion acceptance rejects any indeterminate disposition; completing a previously stopped attempt is not an automatic recovery rule. A duplicate accepted attempt returns the recorded result only if the complete binding agrees; it does not create another event or execute again. Concurrent acceptors serialize and still encounter the same SQL constraints. Replay derives these changes from validated recorded inputs without today's policy or clock.

**Alternative:** One counter for audit, task and control. **Consequence:** Rejected because a consumption event could invalidate its own result or allow unrelated state drift. Separate counters add explicit checks but keep each meaning stable.

### 5. Observer and evaluator trust

**Decision:** Producer registry v1: 1 runtime input normalizer, 2 deterministic policy/capability authority, 3 no-op observer, 4 NoOpV1 evaluator, 5 state/recovery boundary; each has version 1. Registration is compiled/reviewed configuration, not a caller-selected producer string. Persisted kind/producer pair and version must match the registry. Producer IDs are role identities, not OS credentials or cryptographic attestation.

Observer content is exactly the ObservationRecorded schema above, bound through its claim Ref to the full attempt/proposal/task/run/capability identity. A returned observation is produced only after the no-op returns; an interrupted/lost attempt is indeterminate. NoOpV1 evaluator independently recomputes the observation event digest and checks the confirmed reference chain, producer/version, outcome=returned, observed bytes=`NOOP`, criterion=1 and runtime-owned proposal criteria. It emits its own evidence identity/verdict. The state boundary alone applies acceptance rules; neither producer 3 nor 4 has a state-write API. An unknown or substituted producer, cross-attempt evidence or model success text cannot become a verified result.

These are separate modules/procedures in the same runtime process. Independence here is deterministic evaluation separate from proposal/executor claims, not process-compromise resistance. A compromised trusted process can fabricate its own inputs; OS/kernel/root compromise is outside this Phase 2 guarantee. Later worker isolation and real observation sources need separate reviews. Phase 2 rejects approval-required requests; valid human approval integration remains Phase 3 work.

**Alternative:** One producer's success boolean, or separate evaluator services immediately. **Consequence:** The boolean cannot establish independent evidence; extra services add identity/transport work before the no-op boundary is proven. Select separate responsibilities without claiming process isolation.

### 6. Proposed Phase 2 effect qualification

**Decision candidate:** The following names are the complete proposed eligible High list for Phase 2. They are not implemented. This separately reviewed qualification takes effect only after operator acceptance and recorded implementation entry. It does not amend or inherit ADR-0007's Phase 1 list. E means direct/transitive effects; all Mid and pure Low remain transitively pure; Low never calls upward. A procedure not listed has no new permission. No generic dispatcher, callbacks, registry of executable commands or effect interpreter is introduced.

| Eligible High E, planned location | Responsibility | Related High | Pure Mid decisions | Direct reviewed Low dependencies / effects |
|---|---|---|---|---|
| `cmd/warband:main` | Coordinate the selected CLI command | `run_noop` | parse command, describe presentation | read arguments, write selected output, exit |
| `cmd/warband:run_noop` | Coordinate the one no-op task workflow | `append_verified_event` | normalize/authorize/claim/evaluate/accept decisions | observe time, acquire/release writer lock, execute the fixed no-op, capture its bounded observation, write selected result |
| `src/store:append_verified_event` | Coordinate one pledged event append | None | validate event/preconditions | prepare request, SQLite append transaction, read committed bytes, confirm request |
| `cmd/custodian:main` | Coordinate custodian startup/shutdown | `recover_checkpoint`, `serve_loop` | validate configuration/custody paths | read configuration, decode supplied bytes, acquire/release custodian lock, open socket, bind socket, listen, close socket |
| `cmd/custodian:serve_loop` | Repeat the single reviewed request workflow until shutdown | `serve_request` | select stop/continue from supplied status | observe termination request |
| `cmd/custodian:serve_request` | Coordinate one authenticated request | `prepare_checkpoint`, `confirm_checkpoint`, `enroll_checkpoint`, `change_epoch`, `recover_checkpoint` | classify request, authenticate role, describe reply | accept/read bounded local request, read peer credentials, write bounded reply |
| `src/custody:prepare_checkpoint` | Persist one validated pledge | None | decide_prepare, validate link | read custody metadata, append frame, fsync history |
| `src/custody:confirm_checkpoint` | Persist confirmation or return exact replay | `publish_head` | decide_confirm | read custody metadata, append COMMITTED, fsync history |
| `src/custody:publish_head` | Publish selected head bytes durably | None | None | exclusive temporary-file creation, complete write, file fsync, rename, directory fsync |
| `src/custody:recover_checkpoint` | Apply the permitted metadata recovery disposition | `publish_head` | classify_recovery, validate frames/head | read history/head, truncate only selected final suffix, fsync repaired history |
| `src/custody:enroll_checkpoint` | Coordinate authorized empty-store enrollment | `publish_head` | validate enrollment/operator | inspect empty store/custody, read peer credentials, append GENESIS, fsync history |
| `src/custody:change_epoch` | Record separately authorized epoch transition | `publish_head` | validate epoch/operator authorization | read custody metadata/peer identity, append EPOCH, fsync history |

Each listed Low name denotes a narrow fixed technical operation, not a general callback or policy-bearing wrapper. Pure encoding/hashing/parsing are Low; rules over their supplied results are Mid. Pure High may combine only pure Mid. The listed startup/loop procedures have no unlisted effects or imports. A future implementation must map every named operation to its concrete source procedure before review; renaming or splitting does not enlarge the allowed effect set. No unlisted startup exception is granted. All socket, SQLite and filesystem APIs stay behind reviewed Low adapters; no technical handles enter Mid.

**Alternative:** General effectful Mid or unrestricted High-to-Low permission. **Consequence:** Rejected: universal Mid purity and bounded dependencies are preserved at the cost of maintaining an explicit graph. An implementation with additional startup/subflow procedures must return for a scoped graph update, not relabel the same violation.

### 7. SQLite source and integration profile

**Decision candidate:** Pin the official SQLite 3.54.1 amalgamation, not a system SQLite or prebuilt vendor library. [Release notes](https://www.sqlite.org/releaselog/3_54_1.html) identify the release/source; [the download page](https://www.sqlite.org/download.html) publishes its SHA3 digest. Review found a 32-bit heap-buffer-overflow fix plus other reported corrections relative to 3.54.0; this is release review, not a source audit or a claim that no vulnerabilities exist.

| Input | Reviewed identity |
|---|---|
| Source URL | `https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip` |
| Archive size | 2990966 bytes |
| Archive SHA-256, independently computed | `0a9c8e34352dad46006aa82836d5383bff9dc6bc9ce5a60553c05aa30e6ad1f9` |
| Archive SHA3-256, matches upstream | `92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30` |
| sqlite3.c SHA3-256, matches release notes | `e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81` |
| SQLITE_SOURCE_ID, verified in archive header | `2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76` |

The archive and source digests were independently checked against downloaded bytes; no SQLite code was compiled or executed in this documentation task. Future project-local static build: compile only sqlite3.c with the platform-pinned Clang C compiler, `-O2 -fPIC -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DQS=0`, and archive it as `.local/dependencies/sqlite/<source-id>/<target>/libsqlite3.a`. Record the complete compiler/version/flags, archive/object digests, target, compile options and final executable linkage. The proposed static archive is a new reviewed dependency; no runtime build is performed by this amendment. No host SQLite discovery or fallback. Keep the existing Odin/LLVM/runner pins unchanged. Check `sqlite3_libversion_number()==3054001`, exact `sqlite3_sourceid()` and required compile options at startup.

Use a minimal reviewed Odin C-ABI binding to this explicit project-local archive, opaque sqlite3 handles only in Low, and prepared statements with bound values; no SQL from proposals. The pinned Odin source demonstrates `foreign import` and C calling conventions in [core/c/libc/stdlib.odin](https://github.com/odin-lang/Odin/blob/8b35c86efb78e9ab5223673a07e02fc2a6884191/core/c/libc/stdlib.odin#L5-L22). This verifies the available binding mechanism, not a working SQLite integration. A link/build check on Linux x64 and macOS ARM64 is still required before any compatibility claim; there is no existing Warband SQLite binding to reuse.

On every writing connection, set and query `journal_mode=WAL`, `synchronous=FULL`, `foreign_keys=ON`; reject any different effective value. Disable extension loading; use no custom VFS, optional extensions or unsafe synchronization settings. Pin the SQLite schema version at 1 and verify schema/constraints at open. The [SQLite synchronous documentation](https://www.sqlite.org/pragma.html#pragma_synchronous) describes WAL/FULL durability assumptions. Linux fault evidence must identify the actual filesystem, VFS, VM disk/cache/flush profile and SQLite compile options. macOS is functional/encoding development evidence only; it supplies no durability or Linux peer-credential claim. Source retention and clean rebuild proof remain release obligations.

**Alternative:** Independently pinned distribution libraries on each OS. **Consequence:** Project-local source adds a build/patch obligation but avoids changing library behavior under host upgrades. This pin is a proposed input to a later build-tooling PR, not an installed dependency in this task.
