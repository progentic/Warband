# Isolated Linux custodian evidence

Proto owns this isolated implementation. The [target record](../engineering/phase2-entry-review.md#linux-development-target-observed-2026-11-18) identifies the guest kernel, local ext4 filesystem, virtual disk, host cache and compiler. The process keeps custody metadata outside the runtime identity's access. A trusted operator starts the service and handles a stopped service after a storage fault.

## Reproduction

Run in the disposable Ubuntu 24.04 x64 guest with the locked Linux toolchain already built. The harness uses four distinct numeric UIDs, a temporary root-owned directory under /var/lib and transient systemd units. Only the fixture supervisor needs root. The service binds two local Unix sockets. Each client checks the custodian's kernel-reported identity.

```sh
bash scripts/build_custodian.sh
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
  /usr/bin/python3 tests/integration/linux/test_custody_denial.py \
  out/linux_amd64/custodian/normal/custodian \
  out/linux_amd64/custodian/dirsync-fault/custodian
```

## Target run on 2026-11-18

Build and harness exited 0. The custodian ran as UID 50000 at 32 MiB with swap disabled. Each dropped-privilege client checked its actual 256 MiB cgroup and zero swap limit. Runtime, operator and unlisted client UIDs were 50001, 50002 and 50003.

| Experiment | Observed outcome |
| --- | --- |
| First denied enrollment before GENESIS | Injected failure at the directory-sync edge after the first history file sync returned status 14 with a zero receipt. After explicit restart the retained 203-byte frame could be reconciled. A zero-length DB file blocked GENESIS until removed. |
| Successful pre-enrollment denial and process kill | Status 15 carried the caller's durable receipt with zero tip and checkpoint. After SIGKILL, explicit restart and enrollment, authenticated verify retrieved that same frame and record hash. |
| Identity and replay | Operator enrollment and epoch change succeeded. Runtime prepare and confirm returned their original receipts on replay. Runtime administration and all five operations by the unlisted UID were denied. Verify returned the denials in ordinal order with the observed UID, GID and PID. |
| Direct access and diagnostic reads | Runtime read and write opens of both protected files and three attempted path renames returned EACCES (13). With a shortened head, verify returned status 9 and preserved the bytes of both files. |

The first harness invocation stopped before the service started. Systemd returned 217/USER because the numeric test UID had no account entry. The harness now uses setpriv to drop to that UID with an empty supplementary group list before executing the binary. The final build and host transcript is retained locally in `.local/3b/integration-4.log`, SHA-256 `5da2ef883fdf4841d4798e1721666f6d96c679372a61901a856884ee01d35b38`. The normal and fault binary SHA-256 values begin with `559d64f6c1aa` and `4cca59102527`. The successful pre-enrollment receipt was `b4d9f141b85422f73fb16b84359db5e77cf9bbb1725c92cfce61ac1bdd44b02e`.

This run exercises process termination and one sync-error edge. Power interruption, the full durable-boundary crash matrix, measured recovery limits and exactly-once journal import require later evidence. Hosted Linux runs have their own storage identity.

The 21 adjacent custody tests passed on the pinned Linux compiler with vet and warnings-as-errors. Two preliminary invocations failed before test execution, first because the toolchain checkout lacked the tests and then because LLVM's binary directory was missing from PATH. The successful invocation used the transferred workspace package and the build script's LLVM path. Documentation checks and all 28 governance controls passed locally. Local actionlint reports the existing ubuntu-26.04 label on both baseline and candidate.
