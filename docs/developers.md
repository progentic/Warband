# Developer guide

Use this guide to trace the code and understand the architecture. The [constitution](foundation/runtime-constitution.md), [contracts](contracts/README.md), and [accepted decisions](decisions/README.md) govern the design.

## Current implementation

The CLI exposes two commands, `version` and `fixture`. Phase 2 library code operates on supplied bytes and values. Start with the command flow below for the executable, or the [audit and custody modules](#audit-and-custody-modules) for the libraries. The [entry review](engineering/phase2-entry-review.md#slice-3b-gate-0) records what still gates the custodian process.

## Command flow

In [cmd/warband/main.odin](https://github.com/progentic/Warband/blob/main/cmd/warband/main.odin), `main` reads arguments and calls `parse_command`. That function requires exactly one command argument. `describe_command` turns the command enum into a `Presentation`. `write_result` writes it. `main` then exits with its status.

`describe_command` chooses content, stream, format, and status without I/O. Invalid arguments select an explicit error result. They cannot invoke arbitrary commands.

[ADR-0007](decisions/0007-phase1-entrypoint-boundaries.md) limits which High procedures can compose effects. Mid stays transitively pure. Low performs technical operations without calling policy upward. The [effect review](engineering/phase1-effect-composition-review.md) maps these calls. Package separation alone provides no OS sandbox.

## Fixture data

[src/domain/types.odin](https://github.com/progentic/Warband/blob/main/src/domain/types.odin) defines distinct identifiers and `validate_fixture`. Validation checks schema 1 and nonzero task/run IDs. Callers supply the tick.

[src/fixture/codec.odin](https://github.com/progentic/Warband/blob/main/src/fixture/codec.odin) encodes one schema byte and three little-endian u64 values: task, run, and tick. Offsets 1, 9, and 17 produce 25 bytes. See the [independent byte specification](verification/phase1-fixture-specification.md).

`decode` checks length only. `encode` performs no domain validation. Call `validate_fixture` to check parsed values. Codec success grants no authority and proves no task outcome. This fixture does not implement runtime event serialization.

## Event identity

[src/domain/events/identity.odin](https://github.com/progentic/Warband/blob/main/src/domain/events/identity.odin) defines a 16-byte `StoreId` and distinct u64 `Epoch` and `Sequence` types. `EventRef` binds all three. A sequence alone cannot identify an event across stores or epochs.

- `validate_event_ref` rejects empty fields, then checks the supplied expected store and epoch.
- `next_sequence` allows 0 to 1 and rejects overflow.
- `next_epoch` rejects zero and overflow before incrementing.

These pure functions return typed errors. They perform no history lookup, uniqueness check, enrollment, or epoch administration.

## Prepare classification

[src/domain/events/prepare.odin](https://github.com/progentic/Warband/blob/main/src/domain/events/prepare.odin) defines domain values, not wire layouts. `Checkpoint` holds store, epoch, sequence, and head. `Pledge` also binds the predecessor and proposed head/digest.

`classify_prepare` reads supplied values and applies these checks in order:

1. Reject empty or mismatched identity with `InvalidIdentity`.
2. Reject overflow or a sequence other than current + 1 with `InvalidSequence`.
3. Reject a mismatched predecessor sequence/head with `InvalidPredecessor`.
4. If a pending pledge exists, compare every field. Return `PendingReplay` for an exact match. Otherwise return `PendingConflict`.
5. Return `EligiblePledge` when no pending pledge exists.

Earlier failures take precedence. The function never replaces a pledge or advances a checkpoint. Callers still need trusted history, authentication, hash checks, and durable writes. The classifier implements none of those controls.

The [event tests](https://github.com/progentic/Warband/tree/main/tests/odin/event_identity) also cover confirm and recovery classification. Exact committed replay preserves a later pending pledge. Recovery distinguishes an exact pledged event awaiting confirmation from a missing pledged event that requires operator reconciliation.

## Audit and custody modules

- **Event bytes.** The [audit package](https://github.com/progentic/Warband/tree/main/src/audit) implements all ten event kinds, from task creation and proposal recording through evaluation, transition acceptance, rejection, revocation and attempt disposition. Each codec uses the shared envelope and checks the expected store and epoch. The proposal fingerprint binds the entire encoded proposal payload, including its IDs.
- **Custody bytes.** The [record codec](https://github.com/progentic/Warband/blob/main/src/custody/record.odin) handles PENDING, COMMITTED, GENESIS, EPOCH and REJECTION. Variable-size encoders return a fixed buffer and a used length. Pass only the used bytes to the next stage. The [head-file codec](https://github.com/progentic/Warband/blob/main/src/custody/head.odin) handles the materialized checkpoint.
- **History.** The [history validator](https://github.com/progentic/Warband/blob/main/src/custody/history.odin) checks record order, predecessor hashes, pledge pairing, epoch changes and authorization-ID uniqueness against a supplied published head. A denial can precede enrollment. Later denials advance custody history while preserving a pending pledge.
- **Requests and replies.** The [WBCR codec](https://github.com/progentic/Warband/blob/main/src/custody/request.odin) handles prepare, confirm, verify, enroll and epoch change. The [peer decision](https://github.com/progentic/Warband/blob/main/src/custody/peer.odin) checks the supplied listener, operation and observed UID. The [WBRS codec](https://github.com/progentic/Warband/blob/main/src/custody/reply.odin) uses caller-supplied authentication context to redact denial replies and validate receipt cursor bounds. Socket authentication and durable writes belong to the proposed custodian process.

## Repository checks

[check_docs.py](https://github.com/progentic/Warband/blob/main/scripts/check_docs.py) separates inventory reads from pure governance decisions. Its provenance checks validate document fields, not operator identity or commit ancestry.

[run_odin_tests.py](https://github.com/progentic/Warband/blob/main/scripts/run_odin_tests.py) checks exact source discovery, manifest entries, and fresh reports. [Build-manifest publication](engineering/phase1-effect-composition-review.md) writes directly to its destination. It provides no crash-safe replacement guarantee.

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
