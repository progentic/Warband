# Phase 4 increment 2 request recovery

## Qualification boundary

The preproduction x64-review fixture initiated requests under the registered runtime UID and stopped at marker proposal intake. It used the production validator, SQLite writer, independent custodian and recovery procedures. Model input came from deterministic fixtures. The provider call, live operator integration and Phase 4 exit retain their later gates. [Approved scope](../engineering/phase4-increment2-scope.md) · [Decision and fixture requirements](../decisions/0011-atomic-model-request-consumption.md#increment-2-fixtures-owed)

The target ran Ubuntu 24.04 x86-64 on QEMU with ext4, kernel `6.8.0-142-generic`, selected for one boot. The runtime scope used a 256 MiB memory limit and zero swap. The custodian ran under a separate UID in a 32 MiB service with zero swap. The package 2c implementation commit is `bf722baf65cb9b836408c73cd7765fabef473c96`. The build used Odin `8b35c86efb78e9ab5223673a07e02fc2a6884191`, LLVM 19 and the repository-pinned SQLite with WAL/FULL.

## What to reproduce

Build the pinned toolchain and SQLite, provisioner, custodian and reconciliation executables by the Linux Foundation workflow. Run `tests/integration/linux/test_model_request.py` and `tests/integration/linux/test_request_recovery.py` in the same bounded systemd scope. The latter emits JSON lines containing typed recovery outcomes, independently queried canonical bytes, request bindings, custody checkpoint and pledge, inode and xattrs. The hosted job retains the output under `out/linux_amd64/`. The target runs use the normal binary for controls and recovery, and the separate proof binary for exact process stops. The syscall error cases use strace fault injection.

## Dispositions

| Case | Target observation |
|---|---|
| Normal, competing and repeated delivery | One confirmed issue, TaskCreated and kind 11. The consumption row matches the issued ID, Ref, digest and F. The only attempt directory has the two xattrs and an empty file inventory. The task/control projection is 1/0. A fresh duplicate returns Consumed. |
| Early rejection | Unknown ID, stale session, expired ID and mismatched candidate leave the proposal, task, directory and proposal-pledge counts unchanged. Swapping A for B and its digest in SQLite or removing a confirmed expiry row withholds readiness. |
| Six ADR discrepancies | Deletion of the committed row, individual field mutations, substitution of a real foreign proposal Ref, a surviving provenance mark without its row, a row without provenance, and SQLite-only rollback each hold for reconciliation. No recovery invocation admits a replacement proposal. |
| Issuance and expiry interrupts | Before Prepare, recovery can start from the previous head. A missing pledged event holds. After SQLite COMMIT a complete exact pending fact can confirm once. Loss of a confirmed issuer session expires an outstanding request once. |
| Intake interrupts | A directory or task without the required pair retains its hold. Killing either insertion before COMMIT leaves neither row. A spent pair without the synced time proof stays pending. With the exact pair and time proof synced, historical recovery confirms once and returns Ready. |
| Commit deadline | The deterministic window test accepts the millisecond before expiry and rejects equality. Pausing inside SQLite COMMIT and resuming after expiry left the physical pair spent, the proposal pending and the commit-time xattr absent. Recovery withheld Confirm. |
| Storage and bounds | SQLite insertion aborts and a COMMIT veto rolled back both inserts. Injected xattr-write, directory-fsync, WAL-write and WAL-sync errors withheld admission. Unavailable schema, wrong directory permissions, unavailable catalog revision and exhausted row-visit budget withheld progress. |

## Regression boundary

The legacy reader fixtures check that local readers refuse new request histories without changing custody or SQLite. Separate legacy runs cover direct local intake, exact pending read-back, authenticated approval and dispatch refusals, worker confinement, completion and interrupted finalization. Resource measurements qualify only the tested fixture envelope. Filesystem power-loss durability and simultaneous rewriting of SQLite and directory evidence remain outside it.

## Target build identities

| Artifact | SHA-256 |
|---|---|
| Normal request command | `d0c391442549f75733512382f7ba0ca04688dfc58e65408cd596623f96f45ca1` |
| Request proof command | `e88c0839d5ce30d1b85f3a90e52a159cc2e27e9c6b433ed0b6e53bba810ec74b` |
| Custodian | `7621d813dfec3a8f36afea2df81038ff3f5551063e1c5ec21a4cf8e97f52ef0d` |
| Store provisioner | `241763e8d8d3f8469f305b4d0980a2ba44c13d3d011fab571f07f83a6cd6c055` |
| Recovery harness | `86415e90585c657220db808712d254189cfbc210fff176a94cc120c9049b1da1` |

The initial hosted cold-recovery measurement identified a changed debit caller name. The corrected build charges the visit in `append_pledged` and checks the model-specific time witness before Confirm. The original D1 and D2 assertions passed on the target. They reached tips 287 and 330 respectively, with 57,682 and 59,478 measured reconciliation examinations.

## Recorded results

The final fault harness emitted 55 graded records. The competing processes returned `Busy` and `Admitted`; a fresh process returned `Consumed`. The late COMMIT case retained one consumption row and one proposal row at pending tip 6, without a time witness or admission. The synced-witness restart reached confirmed tip 7. Syscall traces captured injected EIO at the provenance write, directory sync, WAL write and WAL sync. Each held the surviving evidence for reconciliation. The 13 named model/replay tests matched their manifest on Linux and macOS. The Linux clock test also passed.

At the 32-request lifetime cap the fixture had 64 confirmed request events, tip 129, zero proposals and a refused 33rd issuance. With a reader holding its snapshot throughout, retained custody history occupied 32,299 logical bytes and the WAL reached 988,832 bytes (995,328 allocated). The database occupied 36,864 bytes and shared memory 32,768 bytes. One fresh recovery took 0.02 seconds at the measurement resolution and reached 4,224 KiB maximum RSS. These figures describe that run on this VM.

| Retained target log | SHA-256 |
|---|---|
| `qualification-final.log` | `032359018a2b916a7f9a92baa61bd3784c78ff587d2d3251a0ec715e01390a9b` |
| `basic-final.log` | `30fb4779ef1e38c48c91e5797c90d056c4008a764a830ad1f43ddcd66dc86fab` |
| `legacy-intake-final.log` | `244f2d4340aa3d39ad9b4f85983bfd9533061a0d42c1f9089134f44b0e41c765` |
| `legacy-worker-final.log` | `b94a5df36ee23ff75f3eeb93afb7d3161dbdd8ef36d4b1e04e712769d2db67dc` |
| `legacy-completion-final.log` | `00379f7210c167310c5df36c5772985336386fed231f27d0607a865aa2854bb8` |
| `debit-final.log` | `e3e3479a20c5fd51db9611299d83ab70dd90364b4b1a6935acbf94a99280ef18` |
