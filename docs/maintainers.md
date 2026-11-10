# Maintainer guide

Use this guide to update, review, and release Warband.

## Check the scope

Read applicable `AGENTS.md` guidance before editing. [project.json](../project.json) declares Phase 2. The [entry review](engineering/phase2-entry-review.md) authorizes pure identity, epoch advancement, and prepare classification only. The CLI still provides the Phase 1 foundation.

Follow the [authority order](governance/README.md#authority-order) when descriptions conflict. Keep design acceptance, implementation permission, and verified behavior separate.

## Important interfaces and calls

Source links pin reviewed baseline `109b8d1`. Check the current files before changing them.

- [cmd/warband/main.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/cmd/warband/main.odin) owns `version` and `fixture`. Success writes stdout and returns status 0. Invalid arguments write stderr and return status 2. [verify_cli.py](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/scripts/verify_cli.py) checks exact output.
- [src/domain/types.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/types.odin) defines distinct IDs, `FixtureSchema`, `Fixture`, and `Error`. Call `domain.validate_fixture(value)` to check schema and IDs.
- [src/fixture/codec.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/fixture/codec.odin) owns `encode`, `decode`, and the 25-byte fixture. `decode(bytes) -> (domain.Fixture, domain.Error)` checks length only. Neither codec function validates schema or IDs. Check those separately.
- [src/domain/events/identity.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/events/identity.odin) defines `StoreId`, `Epoch`, `Sequence`, and `EventRef`. `validate_event_ref(value, store, epoch)` checks an explicit expected scope. Do not use the input's own scope as its authority.
- In that file, `next_sequence(0)` returns 1. `next_epoch(0)` returns `EmptyEpoch`. Both return zero and a typed error on overflow. Check the error before using the value.
- [src/domain/events/prepare.odin](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/src/domain/events/prepare.odin) defines `Pledge`, `Checkpoint`, and `PrepareDecision`. Call `classify_prepare(request: Pledge, current: Checkpoint, pending: ^Pledge)` with `nil` when no pledge exists. It returns `PrepareDecision` and never mutates inputs. A live pledge permits only exact replay. `EligiblePledge` and `PendingReplay` grant no execution authority. The function performs no authentication, hash verification, or durable writes.
- The CLI calls `parse_command`, `describe_command`, then `write_result`. Keep command and presentation decisions pure. Preserve [ADR-0007's reviewed I/O boundaries](decisions/0007-phase1-entrypoint-boundaries.md).
- [toolchain/odin.lock.json](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/toolchain/odin.lock.json) pins compiler and platform profiles. Follow the [build instructions](engineering/phase1-build-and-verification.md). A Mac pass proves no Linux result.

## Update the matching records

1. Identify the affected contract, accepted decision, and existing proof before changing behavior.
2. Align user expectations, security limits, negative paths, and [traceability](verification/traceability-matrix.md). Preserve stable `WB-*` identifiers.
3. Present the [test-necessity case](engineering/coding-standard.md#test-necessity) before adding a test. State the failure, evidence, coverage gap, value, and cost.
4. Update [tests/odin-packages.json](https://github.com/progentic/Warband/blob/109b8d173a753f52682418ac0c299096e452bd0e/tests/odin-packages.json) when test names or packages change. The runner checks exact names and fresh reports.
5. Record material architecture changes in an ADR. Follow the [definition of done](engineering/definition-of-done.md). Passing tests do not close release debt or authorize another phase.

## Handle compatibility

Keep the [fixture specification](verification/phase1-fixture-specification.md) aligned with authorized fixture changes. The fixture does not define runtime event bytes.

Follow [ADR-0005's migration rules](decisions/0005-event-integrity-acceptance-and-recovery.md#custody-frames-head-and-request-framing) for future event or custody schemas. Review version changes, obtain operator permission, and retain original bytes and identities. No runtime codec or migration service exists yet. Review affected evidence when storage, custody, producer trust, or effect boundaries change.

## Validate and hand off

For documentation changes, run:

```sh
python3 scripts/check_docs.py
git diff --check
```

For code or tooling changes, follow the [platform build instructions](engineering/phase1-build-and-verification.md) and [testing standard](engineering/testing-standard.md). Use the manifest for current test counts.

Record the tested source, platform, commands, results, and limits. Check wording against the [documentation standard](engineering/documentation-standard.md). Obtain permission before committing, publishing, merging, or releasing.
