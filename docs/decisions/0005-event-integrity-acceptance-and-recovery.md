# ADR-0005 Event integrity acceptance and recovery

- **Status:** Proposed
- **Decision owner:** Proto, project owner (assigned 2026-10-18)
- **Review status:** Draft; not approved for implementation
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

Use a versioned deterministic binary encoding with a distinct runtime format, not the 25-byte Phase 1 fixture. Primitive widths/order and a kind-specific payload registry must be frozen before implementation.

Proposed envelope fields, in this order:

| Field | Representation and rule |
|---|---|
| Format marker and schema | Fixed runtime marker and explicit schema version; unknown versions rejected |
| Store identity | Fixed-width identity separating histories and identifier namespaces |
| Custody epoch | Explicit epoch identity binding this history segment to its checkpoint authority; stale-epoch requests rejected |
| Audit sequence | Unsigned fixed-width integer; strict monotonic order, no reuse/wrap |
| Event identity | Store identity plus sequence, represented as a distinct domain type |
| Kind | Registered enum with a schema-defined payload; unknown kind rejected |
| Recorded timestamp | Fixed-width integer under an explicitly defined epoch/unit; no native struct layout |
| Task/run/proposal/attempt references | Distinct identifiers with explicit presence encoding and required bindings per kind |
| Producer identity and version | Registered runtime producer, not supplied as authority by the model |
| Payload length and bytes | Bounded, schema-specific canonical encoding; no generic arbitrary map order |
| Previous event hash | Fixed-width hash linking the immediately preceding event |

The proposed link calculation has two domain-separated stages: an event digest over the canonical envelope fields other than the previous-head field, followed by a head hash binding that digest to the custody epoch, store identity, sequence and previous head. The previous head is bound by the link stage, not silently omitted from integrity coverage. The custodian independently recomputes the link from supplied digest and binding fields. The runtime verifies the supplied digest against the exact persisted canonical event. Exact encodings and domain separators remain to be frozen with independent vectors. The runtime supplies ordering, identities and producer metadata; a model-supplied hash or verification flag is never authority. Custodian link checking detects inconsistent calculations, not fabricated content from a compromised authorized runtime.

Integer endianness, identifier widths, epoch/unit, string rules, size limits, genesis bytes, hash algorithm, and complete payload schemas remain review decisions. Proposed defaults are fixed-width little-endian integers, exact bounded UTF-8 bytes without silent normalization, and SHA-256. Reject malformed, ambiguous, duplicate-field, oversized, unknown, or noncanonical representations. A payload codec registry and independent golden vectors are acceptance prerequisites; no implementation may guess omitted fields.

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
| `epoch_change` | Authenticate a separately authorized local operator; bind the exact old epoch/head, proposed new epoch/sequence/head, reason and authorization identity. Preserve the old history and any unresolved pledge. No runtime-accessible reset or automatic cancellation exists. Exact transition and enrollment formats require owner review. |

The old single-step `advance` operation is replaced by prepare/confirm; retaining a bypass would defeat the pledge. Lost prepare and confirm replies are handled by exact replay. Arbitrary older requests, stale epochs and changed tuples are rejected, not treated as idempotent success.

Linux uses connected Unix stream sockets with `SO_PEERCRED`. Authenticate the runtime UID against an explicit allowlist and have the runtime verify the custodian identity. Use a distinct administrative endpoint with an operator UID allowlist excluding the runtime UID. Root is trusted under Option 1. The operation model is transport-independent, but this authentication profile is local-socket-specific; peer identity does not prove executable integrity or honest observations.

Custodian storage is owned by its separate identity and inaccessible to runtime writes. The socket path and storage paths need protected parents, reviewed ownership/modes/ACLs, no untrusted group-writable parents, and no path substitution through symlinks. Required future verification includes actual denied access under the runtime identity, not metadata inspection alone. No such permission evidence exists yet.

### Durable custody records and publication

The append-only custodian history is the recovery source for checkpoint metadata; the current head file is its materialized committed head. Each bounded frame includes its type, epoch/store, full request tuple, previous custody-record hash, length and checksum. PENDING and COMMITTED frames are distinct. Epoch transitions retain their authorization metadata. Hash chaining detects mid-file edits relative to retained trusted records; it does not survive an attacker controlling custodian storage.

For prepare, append the complete PENDING frame and fsync history before replying. For confirm, append the corresponding COMMITTED frame and fsync history first. Then create a new head file exclusively inside the custodian directory, write it completely, fsync it, rename it over the old head on the same filesystem and fsync the directory. Return success only after all required steps complete. Initial creation also requires durable directory entries. Check every write, short write and synchronization result. Head rename and history append are not one atomic transaction.

On restart, a structurally truncated final frame alone may be removed back to the last complete valid frame, durably, before new writes. Never remove a complete frame with a bad checksum or chain link, an earlier damaged record, or a truncated suffix needed to explain the published head. Those are attestation-history faults. Recover a stale head from complete valid COMMITTED custody records only; never regenerate custody history from SQLite. An unmatched final PENDING remains a live pledge after repair. The exact frame layout and hash inputs still require review.

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

An operator recovery action records a disposition; it is not evidence that missing work succeeded. No epoch change suppresses the original fault or creates an authoritative completion. The remaining epoch-transition/genesis specification is a blocker before implementation.

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
