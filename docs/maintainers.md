# Maintainer guide

Use this guide to update, review, and release Warband.

## Check the scope

Read the applicable `AGENTS.md` guidance. The [entry review](engineering/phase2-entry-review.md#slice-3b-gate-0) records completed pure custody work and the activated Linux custodian scope. Review [target evidence](verification/isolated-linux-custodian.md) against the recorded storage stack and UID and memory boundaries. WB-EXC-001 remains open for controlled local inputs.

Follow the [authority order](governance/README.md#authority-order) when descriptions conflict. Keep design acceptance, implementation permission, and verified behavior separate.

## Important interfaces and calls

Source and test links open the current main branch. For a release review, check the same paths at the release commit.

- [cmd/warband/main.odin](https://github.com/progentic/Warband/blob/main/cmd/warband/main.odin) owns `version` and `fixture`. Success writes stdout and returns status 0. Invalid arguments write stderr and return status 2. [verify_cli.py](https://github.com/progentic/Warband/blob/main/scripts/verify_cli.py) checks exact output.
- [src/domain/types.odin](https://github.com/progentic/Warband/blob/main/src/domain/types.odin) defines distinct IDs, `FixtureSchema`, `Fixture`, and `Error`. Call `domain.validate_fixture(value)` to check schema and IDs.
- [src/fixture/codec.odin](https://github.com/progentic/Warband/blob/main/src/fixture/codec.odin) owns `encode`, `decode`, and the 25-byte fixture. `decode(bytes) -> (domain.Fixture, domain.Error)` checks length only. Neither codec function validates schema or IDs. Check those separately.
- [src/domain/events/identity.odin](https://github.com/progentic/Warband/blob/main/src/domain/events/identity.odin) defines `StoreId`, `Epoch`, `Sequence`, and `EventRef`. `validate_event_ref(value, store, epoch)` checks an explicit expected scope. Do not use the input's own scope as its authority.
- In that file, `next_sequence(0)` returns 1. `next_epoch(0)` returns `EmptyEpoch`. Both return zero and a typed error on overflow. Check the error before using the value.
- [src/domain/events/prepare.odin](https://github.com/progentic/Warband/blob/main/src/domain/events/prepare.odin) defines `Pledge`, `Checkpoint`, and `PrepareDecision`. Call `classify_prepare(request: Pledge, current: Checkpoint, pending: ^Pledge)` with `nil` when no pledge exists. It returns `PrepareDecision` and never mutates inputs. A live pledge permits only exact replay. `EligiblePledge` and `PendingReplay` grant no execution authority. The function performs no authentication, hash verification, or durable writes.
- `src/custody/pledge.odin` exposes `encode_pledge(value, store, epoch)`, `decode_pledge(bytes, store, epoch)` and `derive_head(value)`. Supply the expected scope independently. Check typed codec errors before using results; failures return zero values. Preserve exact 136-byte layout and domain/NUL hashing against the independent vectors. These APIs grant no authority or persisted-event guarantee.
- The CLI calls `parse_command`, `describe_command`, then `write_result`. Keep command and presentation decisions pure. Preserve [ADR-0007's reviewed I/O boundaries](decisions/0007-phase1-entrypoint-boundaries.md).
- [toolchain/odin.lock.json](https://github.com/progentic/Warband/blob/main/toolchain/odin.lock.json) pins compiler and platform profiles. Follow the [build instructions](engineering/phase1-build-and-verification.md). A Mac pass proves no Linux result.

### Reviewing audit and custody changes

- For [audit event codecs](https://github.com/progentic/Warband/tree/main/src/audit), compare the changed bytes, digest and linked head with the [independent vectors](verification/adr0005-golden-vectors.json). Exercise the rejection cases for the affected event kind. For a wire-format change, follow the migration rules below.
- For [custody records](https://github.com/progentic/Warband/blob/main/src/custody/record.odin), check all affected frame kinds, used lengths, ordinal and predecessor binding. For [history validation](https://github.com/progentic/Warband/blob/main/src/custody/history.odin), check that denials preserve pending pledges and epoch changes bind the old checkpoint and pending record hash.
- For request or reply changes, use the [custody tests](https://github.com/progentic/Warband/tree/main/tests/odin/custody) to check role separation and disclosure. Administrative requests exclude operator credentials. An unauthenticated denial hides the committed head, pending pledge and custody tip. Authenticated verify replies retain the tip for receipt selection.
- Treat hosted codec results as evidence for the tested representation and pure decisions. Gate 0 calls for separate Linux evidence from real process identities, filesystem access and durable writes before claiming those controls.

## Update the matching records

1. Identify the affected contract, accepted decision, and existing proof before changing behavior.
2. Align user expectations, security limits, negative paths, and [traceability](verification/traceability-matrix.md). Preserve stable `WB-*` identifiers.
3. Present the [test-necessity case](engineering/coding-standard.md#test-necessity) before adding a test. State the failure, evidence, coverage gap, value, and cost.
4. Update [tests/odin-packages.json](https://github.com/progentic/Warband/blob/main/tests/odin-packages.json) when test names or packages change. The runner checks exact names and fresh reports.
5. Record material architecture changes in an ADR. Follow the [definition of done](engineering/definition-of-done.md). Passing tests do not close release debt or authorize another phase.

## Handle compatibility

Keep the [fixture specification](verification/phase1-fixture-specification.md) aligned with authorized fixture changes. The fixture does not define runtime event bytes.

Follow [ADR-0005's migration rules](decisions/0005-event-integrity-acceptance-and-recovery.md#custody-frames-head-and-request-framing) for future event or custody schemas. Review version changes, obtain operator permission, and retain original bytes and identities. All ten audit event kinds have codecs. A migration procedure remains planned. Review affected evidence when storage, custody, producer trust, or effect boundaries change.

## Validate and hand off

For documentation changes, run:

```sh
python3 scripts/check_docs.py
git diff --check
```

For code or tooling changes, follow the [platform build instructions](engineering/phase1-build-and-verification.md) and [testing standard](engineering/testing-standard.md). Use the manifest for current test counts.

Record the tested source, platform, commands, results, and limits. Check wording against the [documentation standard](engineering/documentation-standard.md). Obtain permission before committing, publishing, merging, or releasing.
