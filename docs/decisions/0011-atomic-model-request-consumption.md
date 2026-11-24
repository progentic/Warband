# ADR-0011: Consume the model request with marker proposal intake

## Status

Proto selected Option A for Phase 4 increment 2. The decision takes effect on protected merge. Its baseline is the [increment 1 merge](https://github.com/progentic/Warband/commit/525b2cce0ccc2d1fbb19ae78677074cc61623625). Implementation, integration and runtime activation retain their separate scopes.

## Decision

An operator's request can admit one marker proposal. Before egress, the runtime durably issues a unique request ID bound to the selected catalog intent in the trusted store. The isolated adapter has no store access. At reply time the runtime requires a matching outstanding issuance and the [validated catalog selection](../engineering/phase4-entry-review.md#increment-1-scope-for-pure-candidate-validation). An unknown, expired, consumed or mismatched ID is rejected before starting intake, including before creating a directory, task or custody pledge.

Under the existing writer gate, check issuance, expiry and prior consumption before intake effects. In the same SQLite WAL/FULL transaction that inserts kind 11, require the matching outstanding issuance and insert one consumption record unique to the issued ID. Record the request ID, catalog identity, catalog payload digest, full proposal Ref, event digest and proposal fingerprint F. The runtime only inserts consumption records. Issuance and expiry are separate bookkeeping. If either insert fails, roll back both. Competing deliveries must observe at most one committed pair. A fresh operator initiation gets a fresh ID.

Provision the auxiliary request schema explicitly and verify it before use. Normal service cannot create or repair it. It holds durable admission state of its own. The existing kind-11 bytes contain no provider request ID, so event replay cannot reconstruct that state. Task and control projections continue to derive from confirmed events. The [acceptance index](../engineering/phase3-entry-review.md#complete-a-marker-attempt) provides the provisioning precedent only.

## Verifying the binding

Record the request ID as model provenance on the original runtime-controlled attempt directory, separate from the worker's marker payload. Before trusting a consumption, resolve its full Ref in custody-confirmed history, require a kind-11 proposal and recompute the event digest, F and complete payload digest. Compare the proposal's attempt and directory identity with the actual directory and its provenance. Check the catalog identity against the intent originally issued for this request and the canonical example against the proposal bytes.

Inventory both directions before admitting another request. Every attempt with model provenance requires exactly one matching consumption. Every consumption requires the matching provenance on the directory identified by its event. For a pending pledge, first verify the pair against the exact pledged bytes and surviving directory. Historical Confirm may then finish. Trust the binding as confirmed only after the event is covered by custody.

Kind 11 has no request ID or catalog identity. Recomputing F cannot detect a change to those fields alone. The implementation scope must identify what protects the request-to-intent binding against a SQLite rewrite, including substitution of a different catalog identity with identical bytes. It must also specify provenance write and sync ordering, protection from modification and retention for as long as recovery relies on the directory. A provenance write and SQLite commit are separate durable operations. A one-sided result requires reconciliation even when caused by interruption.

## Crash and recovery dispositions

| Surviving evidence | Required disposition |
|---|---|
| Issuance missing or uncertain | Withhold egress. Reject an unknown reply ID. Never reconstruct issuance from the reply. |
| Stale issuance with neither consumption nor kind 11 committed | With no conflicting provenance, expire the ID durably and record the audit disposition. Discard the volatile candidate. A fresh operator request may proceed only when the store is ready. |
| Attempt directory, earlier task event or a custody Prepare survived before the pair committed | Preserve the existing intake hold. In particular, a missing pledged event requires operator reconciliation. Expiring an issuance cannot clear a pledge or authorize a replacement proposal. |
| Pair committed before Confirm | The ID is spent. Read back the exact event, consumption binding and directory provenance. Only the existing custody path may finish confirmation of the already pledged event, subject to its directory, history and integrity checks. Withhold acknowledgment until confirmation. |
| Confirmed pair, including after a lost reply | Reject repeated admission. Preserve the binding and confirmed proposal. |
| Missing, conflicting or unverifiable binding or store | Withhold model intake, preserve the evidence and report the discrepancy. Event replay cannot recreate a lost request table. |

Request recovery expires stale issuances and reports discrepancies. It never initiates intake, voids consumption or makes an ID reusable. Historical custody confirmation cannot recreate a live grant. If audit persistence is unavailable, report that uncertainty. [Event integrity and failure behavior](../contracts/event-integrity.md)

## Rationale and verification

A separate consume-first journal would spend the ID before the proposal transaction and require a second durability mechanism. Option A removes that split commit. Earlier intake effects and the custody confirmation boundary still have their own recovery dispositions.

A SQLite-only rollback across a consumed proposal must be detected against surviving custody history and attempt provenance. The scope assumes those witnesses remain intact. Whole-system rollback is outside the qualified envelope. Changes confined to issuance or expiry before any witnessed proposal need their own integrity argument. [Store threat model](../security/trust-model.md)

### Increment 2 fixtures owed

Run the real writer and recovery path. Each discrepancy below requires operator reconciliation, preservation of surviving evidence, and zero new admissions.

| Fixture | Independent comparison |
|---|---|
| Delete a previously committed consumption row | Locate the request through surviving model provenance and the confirmed proposal. |
| Alter a binding field | Compare event and payload digests and F against the confirmed event. Exercise request-ID and catalog-identity changes against the independent intent and provenance evidence. |
| Retarget the Ref to another valid proposal | Reject even if the payload matches. Check the full event and original attempt binding. |
| Retain provenance without a consumption | Interrupt at the filesystem/SQLite boundary. Preserve the one-sided evidence without inventing a consumption. |
| Retain a consumption without matching provenance | Withhold admission if the original request mark is missing or names a different ID. |
| Restore only SQLite to a pre-consumption snapshot | Compare the older store with the retained custody tip and directory inventory. |

Also race duplicate deliveries, interrupt issuance and both sides of the pair commit, and lose a confirmation reply. Inspect proposal count, consumption records, custody and audit dispositions. Require at most one committed pair, zero ID reuse and zero recovery-initiated proposals. These are verification obligations for implementation. [Phase 4 traceability](../verification/traceability-matrix.md#phase-4-provider-and-operator-workflow)

## Package 2a request event profile

WBEV version 2 uses the existing 56-byte header, 32-byte previous head, event digest and custody link algorithms. Producer 9 version 1 is the authenticated runtime request issuer. The producer code alone grants no access. All numbers are little-endian unsigned integers. IDs on wire occupy 16 raw nonzero bytes. The API request ID is their 32-character lowercase hexadecimal encoding.

| Kind | Payload fields in wire order | Total event bytes |
|---|---|---:|
| 18 RequestIssued | Request ID, Linux boot ID, runtime-session ID, catalog revision u32, catalog ID u32, SHA-256 of complete catalog bytes (32 bytes), issue and exclusive deadline BOOTTIME ticks (u64 milliseconds each) | 192 |
| 19 RequestExpired | Full 32-byte issuance Ref, echoed request ID, reason u8 (1 deadline, 2 cancellation, 3 session loss) | 137 |

The issuer samples the current boot and session. Both catalog numbers are nonzero. Revision 1 fixes ID 1 to empty bytes and ID 2 to ASCII `abc`. Preserve this revision for recovery. Validate one to 32 catalog entries, unique IDs, payloads and SHA-256 digests. Raw payloads remain bounded by the marker limit. Unknown revisions or IDs withhold admission. The codec records the claimed digest. The runtime must compare that witness with the retained catalog before any intake effects.

The deadline is positive, at most signed 64-bit maximum and at most 30,000 milliseconds after the supplied start. Admission requires the issuing session and boot, and fresh BOOTTIME strictly before expiry. A reason code in history records the issuer's disposition. Replay verifies its reference and uniqueness and does not consult the current clock.

Request-aware replay returns only custody-confirmed issuance and expiry facts. A request ID is unique across the projected store, including across epochs. Expiry must refer to the exact earlier issuance in the same epoch and can appear once. Request facts leave task/control versions unchanged. They cannot establish consumption in isolation. Both existing replay entry points reject histories containing these kinds. A failure returns no partial request projection.

**Bounded fixture profile.** At most 32 issuances per retained store history, including expired IDs. Reserve capacity before Prepare. One issue/expiry pair adds 329 canonical event bytes and four 251-byte custody frames. At the cap this is 10,528 canonical bytes and 32,128 logical custody bytes. A full read of these 64 events adds 64 row fetches, integrity checks and reducer visits apiece, plus at most 32 ID comparisons per request fact. Charge repeated scans and refuse work at ADR-0008 budgets. SQLite page and peak WAL growth, projection memory and elapsed recovery time require measurement in 2d before accepting a live envelope.

**Independent packing vectors.** The replay fixture includes both complete literal records, packed separately with Python little-endian struct encoding and hashlib SHA-256. Use store, request, boot and session filled with 01, 02, 03 and 04 hex respectively. Use epoch 1, sequences 1/2, recorded times 10/11, genesis head filled with 55 hex, revision 1, ID 2, elapsed interval [1,000, 31,000) and expiry reason 1. The issuance digest is `28258c98886cea35ebe0ac23874348fcc4610cfcea3e3eaf79e93aa521accca4`, its head `bbd96add826fe7131d4e285561b0c1ecb9e1561237f99a3b817c8143846d5605`. The linked expiry digest is `2079c553335bf58069b0d0a9292ae7366d21f7cc676288f6783f588c61c9e840`, its head `5dcf7362ed36e3ceed328bfb6117a5a99366e1358fb87fcab1be33a264113f16`.
