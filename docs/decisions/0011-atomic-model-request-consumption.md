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
