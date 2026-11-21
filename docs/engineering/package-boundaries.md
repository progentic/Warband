# Package Boundaries

Each package must have one clear owner and one clear reason to exist.

## `domain`

Defines identifiers and immutable vocabulary. It does not authorize, execute, store, or mutate.

## `runtime`

Coordinates work. It does not bypass policy, evaluation, capability, or state-transition rules.

## `policy`

Returns explicit policy decisions. It does not run tools or commit state.

## `capability`

Issues, verifies, expires, and revokes narrow execution rights.

## `execution`

Runs approved actions within resource and time limits.

## `evaluation`

Turns observations into evaluation results. It does not claim authority over state.

## `state`

Owns authoritative state and valid transitions.

## `audit`

Records and verifies tamper-evident history.

## `model`

Adapts model providers into the proposal interface. It remains outside the trusted authority core.

## `tools`

Implements bounded actions. Tools may not call each other unless a documented execution plan permits it.

## Implemented Phase 1 packages

`cmd/warband` owns command routing and presentation. `src/domain` owns distinct identifiers, typed errors, and pure fixture validation. `src/fixture` owns fixed-width byte encoding/decoding through the Odin endian library. It does not authorize or accept facts. `tests/odin-packages.json` enumerates the foundation tests.

`gateway` and `recovery` remain planned boundaries referenced by traceability. Neither is implemented in Phase 1; their contracts and ownership need follow-on decisions before execution begins. All other runtime packages listed above remain planned.

## Implemented pure custody codec

`src/custody` owns the fixed pledge representation/link hash, PENDING/COMMITTED frame representation and materialized head bytes under Proto's bounded Phase 2 authorization. Its supplied-value codecs and technical endian/SHA-256 helpers do not authenticate, store, mutate custody or accept facts. All five frame kinds now use a [shared core with payload delegation](../decisions/0005-event-integrity-acceptance-and-recovery.md#all-kind-custody-framing-authorized-2026-11-16); the isolated Linux process and its private adapter package are mapped in the [custodian implementation record](../decisions/0005-event-integrity-acceptance-and-recovery.md#isolated-linux-custodian-implementation-2026-11-18); [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#pledge-encoding-and-link-hashing-recorded-2026-11-12) records the exact dependency and verification boundary.

## Implemented event codecs

`src/audit/task_created.odin` owns pure TaskCreated encoding, decoding and event-body hashing. It imports event-domain vocabulary and the same approved endian/SHA-256 dependencies as the pledge codec. Tests compose its digest with `custody.derive_head`; production audit code has no custody, storage or state-writer dependency. `src/audit/proposal_recorded.odin` adds kind 2 through the shared envelope/hash implementation in `envelope.odin`; [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#proposalrecorded-codec-authorized-2026-11-16) records its scope. `src/audit/authorization_recorded.odin` adds kind 3/producer 2 through the same helpers; its [ADR record](../decisions/0005-event-integrity-acceptance-and-recovery.md#authorizationrecorded-codec-authorized-2026-11-16) defines representation and forward-reference checks. `src/audit/dispatch_claimed.odin` adds kind 4 using the unchanged envelope; its [ADR record](../decisions/0005-event-integrity-acceptance-and-recovery.md#dispatchclaimed-codec-authorized-2026-11-16) records representation-only scope. `src/audit/observation_recorded.odin` adds kind 5 with outcome-derived bytes; its [ADR record](../decisions/0005-event-integrity-acceptance-and-recovery.md#observationrecorded-codec-authorized-2026-11-17) defines the representation boundary. The [evaluation and transition codecs](../decisions/0005-event-integrity-acceptance-and-recovery.md#evaluationrecorded-and-transitionaccepted-codecs-authorized-2026-11-17) add kinds 6 and 7 in the same audit package. The [revocation and attempt disposition codecs](../decisions/0005-event-integrity-acceptance-and-recovery.md#capabilityrevoked-and-attemptdisposition-authorized-2026-11-17) add kinds 9 and 10. The [RejectionRecorded codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#rejectionrecorded-codec-authorized-2026-11-17) handles kind 8 and its optional reference.

Frame/head codecs reuse package-private endian operations and a shared metadata-domain SHA-256 helper. Frame encoding delegates pledge validation to the existing codec. Head decoding verifies representation and supplied scope; it does not establish trust in the referenced custody record.

`src/custody/genesis.odin`, `epoch.odin` and `rejection.odin` own pure administrative/rejection payloads and their specified hashes. Shared private identity/reason validation serves both administrative formats; reason validation uses the pinned standard-library UTF-8 implementation. AuthorizationId remains domain vocabulary. Payload serialization supplies no operator authority or custody mutation.

Custody also owns the [WBCR codec and pure peer decision](../decisions/0005-event-integrity-acceptance-and-recovery.md#pure-custodian-requests-and-peer-roles-authorized-2026-11-17). The caller supplies listener identity and observed credentials; socket acquisition and filesystem effects require separate authorization.

The [WBRS reply codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#wbrs-replies-and-disclosure-authorized-2026-11-17) receives authentication and request expectations from the caller. It validates the wire representation and enforces disclosure before exposing a reply value.


## SQLite writer open

`src/store` owns the verified writer handle and its open-time profile. Only the private SQLite adapter in this package calls the C ABI. The caller receives an owned writer after all profile checks succeed, can inspect a copy of its observed settings, and closes it once. The integration fixture owns database creation. [Qualified procedures and evidence](../decisions/0005-event-integrity-acceptance-and-recovery.md#sqlite-writer-open-qualification)

## Isolated receipt importer

`cmd/reconcile-custody` accepts the installed segment paths, epoch handoffs, custodian socket and trusted UID. `src/runtime` coordinates recovery and cursor paging. Its client package authenticates the connected server before sending a WBCR request. `src/store` keeps statements and raw SQLite handles private and validates read-back before sending exact confirmation. [Effect edges and recovery evidence](../decisions/0005-event-integrity-acceptance-and-recovery.md#isolated-linux-receipt-reconciliation-qualification)
