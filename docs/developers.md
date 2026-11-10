# Developer guide

Use this guide to trace the code and understand the architecture. The [constitution](foundation/runtime-constitution.md), [contracts](contracts/README.md), and [accepted decisions](decisions/README.md) govern the design.

## Current implementation

[project.json](../project.json) declares Phase 2. The [entry review](engineering/phase2-entry-review.md) authorizes pure identity, epoch advancement, and prepare classification only. The CLI still exposes Phase 1 commands. Warband has no runtime gateway, policy engine, evaluator, state writer, database, custodian, or execution tool yet.

Source links pin reviewed main baseline `109b8d1`.

## Command flow

In [cmd/warband/main.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/cmd/warband/main.odin), `main` reads arguments and calls `parse_command`. That function requires exactly one command argument. `describe_command` turns the command enum into a `Presentation`. `write_result` writes it. `main` then exits with its status.

`describe_command` chooses content, stream, format, and status without I/O. Invalid arguments select an explicit error result. They cannot invoke arbitrary commands.

[ADR-0007](decisions/0007-phase1-entrypoint-boundaries.md) limits which High procedures can compose effects. Mid stays transitively pure. Low performs technical operations without calling policy upward. The [effect review](engineering/phase1-effect-composition-review.md) maps these calls. Package separation alone provides no OS sandbox.

## Fixture data

[src/domain/types.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/types.odin) defines distinct identifiers and `validate_fixture`. Validation checks schema 1 and nonzero task/run IDs. Callers supply the tick.

[src/fixture/codec.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/fixture/codec.odin) encodes one schema byte and three little-endian u64 values: task, run, and tick. Offsets 1, 9, and 17 produce 25 bytes. See the [independent byte specification](verification/phase1-fixture-specification.md).

`decode` checks length only. `encode` performs no domain validation. Call `validate_fixture` to check parsed values. Codec success grants no authority and proves no task outcome. This fixture does not implement runtime event serialization.

## Event identity

[src/domain/events/identity.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/events/identity.odin) defines a 16-byte `StoreId` and distinct u64 `Epoch` and `Sequence` types. `EventRef` binds all three. A sequence alone cannot identify an event across stores or epochs.

- `validate_event_ref` rejects empty fields, then checks the supplied expected store and epoch.
- `next_sequence` allows 0 to 1 and rejects overflow.
- `next_epoch` rejects zero and overflow before incrementing.

These pure functions return typed errors. They perform no history lookup, uniqueness check, enrollment, or epoch administration.

## Prepare classification

[src/domain/events/prepare.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/events/prepare.odin) defines domain values, not wire layouts. `Checkpoint` holds store, epoch, sequence, and head. `Pledge` also binds the predecessor and proposed head/digest.

`classify_prepare` reads supplied values and applies these checks in order:

1. Reject empty or mismatched identity with `InvalidIdentity`.
2. Reject overflow or a sequence other than current + 1 with `InvalidSequence`.
3. Reject a mismatched predecessor sequence/head with `InvalidPredecessor`.
4. If a pending pledge exists, compare every field. Return `PendingReplay` for an exact match. Otherwise return `PendingConflict`.
5. Return `EligiblePledge` when no pending pledge exists.

Earlier failures take precedence. The function never replaces a pledge or advances a checkpoint. Callers still need trusted history, authentication, hash checks, and durable writes. The classifier implements none of those controls.

The [event tests](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/tests/odin/event_identity/event_identity_test.odin) cover identity, arithmetic, and six classifier cases. The [manifest](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/tests/odin-packages.json) lists three packages and nine tests. These tests prove partial domain behavior, not runtime replay or durability.

## Repository checks

[check_docs.py](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/scripts/check_docs.py) separates inventory reads from pure governance decisions. Its provenance checks validate document fields, not operator identity or commit ancestry.

[run_odin_tests.py](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/scripts/run_odin_tests.py) checks exact source discovery, manifest entries, and fresh reports. [Build-manifest publication](engineering/phase1-effect-composition-review.md) writes directly to its destination. It provides no crash-safe replacement guarantee.

## Accepted design: future runtime

The [architecture](architecture/README.md) and [package boundaries](engineering/package-boundaries.md) separate proposal, policy, execution, evaluation, and state acceptance. The model proposes data. Policy decides. The executor acts within limits. Evaluators check observations. Only the state boundary accepts eligible facts.

The [pipeline](architecture/execution-pipeline.md) records audit events at each security-relevant stage. [ADR-0005](decisions/0005-event-integrity-acceptance-and-recovery.md) accepts a deterministic no-op design. Warband has not implemented this pipeline.

### State and evidence

The [state model](architecture/state-model.md) derives audit and authoritative views from one event history. Claims can appear in audit without becoming task facts. Indexes remain reconstructible.

Task version, control revision, and attempt identity serve different purposes. Acceptance checks expected versions, capability state, evidence references, and scoped uniqueness. One transaction performs those checks and inserts the event and indexes.

### Custody and recovery

A hash chain alone cannot expose every rewrite or missing suffix. The design adds a separate custodian OS identity on the same VM. It keeps a trusted checkpoint outside runtime write access.

The [writer protocol](decisions/0005-event-integrity-acceptance-and-recovery.md#writer-ordering-and-visibility) prepares a durable pledge, commits SQLite, then confirms custody. Only then may the runtime acknowledge, dispatch, or publish authoritative results. Readers expose the confirmed prefix.

Exact replay can recover a lost reply. A missing pledged event requires operator reconciliation. The runtime cannot automatically trust an unpledged tail or call an uncertain commit a rollback. The ADR defines exact bytes, hashes, and crash cases.

### Trust limits

The observer and evaluator share one trusted process. Producer IDs identify roles, not OS credentials or honest behavior after compromise. Custody proves neither observation truth nor execution permission.

Replay uses validated recorded inputs, not today's policy, clock, model, or tools. The design targets at-most-once accepted transitions. It does not promise exactly-once external effects or permit automatic redispatch after uncertain execution.

The design trusts VM root, kernel, administrator, and storage behavior. It cannot detect whole-VM rollback or control of both custody domains. Read the [trust model](security/trust-model.md), [threat model](security/threat-model.md), and [verification plan](verification/phase2-verification-plan.md) for the required future proofs.

## Read technical requirements

`MUST` requires compliance. `MUST NOT` prohibits behavior. `SHOULD` expects compliance unless a documented reason justifies an exception. `SHOULD NOT` means you should normally avoid the behavior. `MAY` permits a choice. An `INVARIANT` holds in every valid state.

Keep user, engineering, security, and verification contracts aligned. Follow the [documentation standard](engineering/documentation-standard.md) and [authority order](governance/README.md#authority-order). Repository records govern. Chats, memory, saved responses, and examples provide working context, not accepted decisions.
