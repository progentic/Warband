# ADR-0005 Event integrity acceptance and recovery

- **Status:** Proposed
- **Decision owner:** Unassigned
- **Review status:** Draft; not approved for implementation
- **Scope:** Proposed Phase 2 deterministic no-op authority boundary
- **Supersedes:** None
- **Related decisions:** Accepted ADR-0001 through ADR-0003; Proposed ADR-0004
- **Authorization:** Design only. Neither this draft nor Phase 1 acceptance authorizes Phase 2 code.

## Context

The foundation has local Linux x64 and macOS ARM64 evidence. It does not yet execute proposals, consume capabilities, verify external observations, commit runtime facts, or replay an authoritative event store.

The next boundary must answer: how can Warband prove that an action used the correct authority, generated trustworthy evidence, and produced at most one valid authoritative transition across failures and restarts?

The constitution remains authoritative. This draft proposes mechanisms beneath it; it does not weaken the contracts or claim unimplemented guarantees.

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
| Audit sequence | Unsigned fixed-width integer; strict monotonic order, no reuse/wrap |
| Event identity | Store identity plus sequence, represented as a distinct domain type |
| Kind | Registered enum with a schema-defined payload; unknown kind rejected |
| Recorded timestamp | Fixed-width integer under an explicitly defined epoch/unit; no native struct layout |
| Task/run/proposal/attempt references | Distinct identifiers with explicit presence encoding and required bindings per kind |
| Producer identity and version | Registered runtime producer, not supplied as authority by the model |
| Payload length and bytes | Bounded, schema-specific canonical encoding; no generic arbitrary map order |
| Previous event hash | Fixed-width hash linking the immediately preceding event |

Compute the event hash from a domain-separated hash input containing the canonical envelope, including the previous hash. The runtime supplies ordering, identities, producer metadata, and hashes. Never accept a model-supplied hash or verification flag as authority.

Integer endianness, identifier widths, epoch/unit, string rules, size limits, genesis bytes, hash algorithm, and complete payload schemas remain review decisions. Proposed defaults are fixed-width little-endian integers, exact bounded UTF-8 bytes without silent normalization, and SHA-256. Reject malformed, ambiguous, duplicate-field, oversized, unknown, or noncanonical representations. A payload codec registry and independent golden vectors are acceptance prerequisites; no implementation may guess omitted fields.

Proposal fingerprints use a separate domain/schema from event hashes. Bind the normalized tool, arguments, target, expected effect, task/run, policy version, approval requirements, and recovery disposition. The runtime owns allowed effect criteria; a proposal cannot weaken its own success test.

## Integrity and trusted heads

A hash chain alone cannot detect deletion of a valid suffix or a complete rewrite when the attacker also supplies the expected head. Verification needs an independently trusted store identity, sequence, and hash checkpoint covering the history being trusted.

Propose a protected-head interface whose custody is outside the journal-rewrite attacker's control. Checkpoints are integrity metadata, not a second event ledger. The first phase must define its concrete custodian/backend and threat assumptions; no automatic remote anchoring service is authorized by this draft.

The trusted head must cover every security event acknowledged as durable before dispatch or publication. If an append succeeds but protected-head advancement fails, stop dispatch/publication and record an integrity/recovery condition when storage permits. Do not report that durable bytes disappeared or that a locally committed write was rolled back. On restart, missing anchored records, conflicting heads, or a suffix whose origin cannot be established block authoritative replay and require reconciliation.

Anchor latency, atomicity, unacknowledged-tail handling, genesis trust, and crash recovery between journal and head writes remain blocking design questions. The event-integrity contract's four viewpoints must specify the resulting detection scope before this ADR can be accepted. No guarantee against an attacker controlling both journal and checkpoint custody is claimed.

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

SQLite is a candidate implementation for the first local transactional store, not selected by this draft. Durability, constraints, locking, checkpoint integration, migrations and power-loss assumptions require review. Do not add a second authoritative database or rewrite prior accepted ADRs to justify storage shortcuts.

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

Before acceptance, assign an owner; freeze the complete wire/payload and transition registries; choose/review storage durability and checkpoint custody; resolve journal/head crash windows and task/control version rules; define the observer/evaluator trust boundary; and reconcile procedure-layering/effect dispatch without placing I/O in pure domain rules. High orchestration, pure decisions and technical adapters must be reviewed against repository guidance; no exception is silently accepted here.

On acceptance, align authoritative-state, model-proposal, independent-evaluation and event-integrity contracts, security/trust/threat documents, execution pipeline, package/dependency ownership, negative paths and traceability. Preserve existing identifiers; add new cases for newly specified failures. Authorize Phase 2 implementation separately, beginning with the deterministic no-op and the required rejection/crash/replay proofs.
