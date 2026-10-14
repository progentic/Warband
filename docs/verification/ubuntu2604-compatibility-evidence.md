# Native Ubuntu 26.04 compatibility evidence

## Scope and baseline

Owner-selected ADR-0006 Option A is compatibility evaluation only. ADR-0006 remains Proposed; no merge, promotion, production architecture or Phase 2 implementation is authorized. Draft [PR #5](https://github.com/progentic/Warband/pull/5) uses branch `ubuntu-2604-compatibility`, based on v0.0.1 / `3675dca25fd68c867cfb4ed5d9bbcddd545d57aa`. Main and the baseline tag remain unchanged.

The primary Linux job remains `Phase 1 Linux Foundation` on `ubuntu-latest`, with the default Ubuntu 24.04 `linux` profile. `validate` and `Phase 1 macOS Portability` retain their names. The new compatibility job is separate, read-only, credential-free, bounded to 30 minutes and retains only `out/` evidence for 30 days, including on failure. All external action SHAs are unchanged.

## Independently inspected baseline

The v0.0.1 [hosted run](https://github.com/progentic/Warband/actions/runs/38284823573) produced Linux archive digest `0da3d216f0cd6e0454a913dc178c56cb89f4f3929c88d4b474849f28bb415790`. The downloaded archive digest matched GitHub metadata. The binary SHA-256 matched its manifest: `a5e539bcd87fb045636bf855b41ffc44a72edf98a64ccff427f8ffe41e4e0bc8`. Independent header inspection confirmed ELF64 little-endian machine 62 (x86-64). The manifest records runner `ubuntu24` / `20261004.327.1`, Odin source `8b35c86efb78e9ab5223673a07e02fc2a6884191`, LLVM/Clang 19.1.1 and libc/libm linkage.

| Input | Verified Ubuntu 24.04 baseline | Explicit Ubuntu 26.04 candidate |
|---|---|---|
| LLVM/Clang/LLD packages | `1:19.1.1-1ubuntu1~24.04.2` | `1:19.1.7-20ubuntu4` |
| LLVM/Clang reported versions | 19.1.1 | 19.1.7 required |
| `libstdc++-14-dev` | `14.2.0-4ubuntu2~24.04.1` | `14.3.0-14ubuntu1` |
| Make | `4.3-4.1build2` | `4.4.1-3` |
| GNU binutils | `2.42-4ubuntu2.10` in the unchanged-profile recheck; not retained in the original five-package receipt | `2.46-3ubuntu2` |
| System libc receipt | `2.39-0ubuntu8.9` | `2.43-2ubuntu2.4` |
| ELF GNU ISA-needed property | x86-64-baseline (mask 1) | x86-64-baseline/v2/v3 (mask 7) |
| Provenance | Ubuntu Noble signed repositories | Ubuntu Resolute signed repositories |
| Odin SHA / upstream build-script SHA-256 | `8b35c86efb78e9ab5223673a07e02fc2a6884191` / `d55a0cc0ac702a8697bbfe048966fa7d4f74377ce5c7f66bd853fce1cf1de206` | Identical |

Original `linux` and `macos` lock objects are preserved. The candidate's LLVM revision applies to Clang, LLVM development files and LLD. Its three other direct packages are separately pinned. Existing Ubuntu APT signature/hash checks remain enabled; no repository, package manager, compiler source or fallback was added. Transitive installed receipts and package metadata are retained; a durable dependency archive and recovery proof remain independent work.

## Actual discovery and correction

The [native discovery run](https://github.com/progentic/Warband/actions/runs/38504018584), head `318ea03`, reports Ubuntu 26.04.1 LTS, x86-64, image `ubuntu26` / `20260927.149.1`. Its artifact digest `f14dfb6b5c3fd4687c25b45740bb582b537974ebb2562bcfffa559c34a1ccf68` matched downloaded bytes. Actual APT policy supplied the candidate revisions above, including GCC 14 headers. Newer LLVM packages were available but were not selected. This inspection pass alone is not a compiler/build pass.

The first full candidate at `66d7036` [failed before installation](https://github.com/progentic/Warband/actions/runs/38504532030): evidence capture assumed `/etc/apt/apt-security-mirrors.txt` existed. The correction records available mirror-list files; actual source definitions, Ubuntu signing keys and fail-closed APT update remain required. No toolchain test executed in that failed job, and no compatibility pass is attributed to it.

## Commands and verification discipline

On the native candidate only:

```sh
export WARBAND_TOOLCHAIN_PROFILE=linux_ubuntu2604
export LLVM_CONFIG=/usr/bin/llvm-config-19
export CXX=/usr/bin/clang++-19
export CXXFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/14
bash scripts/install_linux_toolchain.sh
bash scripts/build_odin.sh linux_amd64
bash scripts/build_warband.sh linux_amd64
python3 scripts/check_docs.py
python3 -m unittest discover -s tests/governance -v
python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-linux_amd64/odin --output out/linux_amd64/tests
python3 scripts/verify_cli.py out/linux_amd64/warband
```

The job requires a fresh compiler directory and uses no compiler cache. It records OS/kernel/image, package architecture, source definitions/signing keys, direct package revisions and metadata/hashes, installed dependency receipts, compiler identity/header/hash/linkage, GNU/LLD versions, selected C++ headers, Warband architecture/linkage/manifest and original test reports. Native x64 compatibility does not select a production CPU baseline or prove runtime isolation.

No tests or fixtures were added. Existing exact-version controls, governance controls, two Odin packages/five named tests and static CLI/golden expectations are reused. Profile keys are explicitly enumerated; installer/build compare exact OS identity, and version selection rejects incompatible profile/platform pairs before querying tools. There is no retry under a different dependency profile.

Local documentation governance, all 22 Python controls, shellcheck and diff validation passed. Local actionlint's label inventory predates `ubuntu-26.04`: the full run reports that one unknown-label diagnostic. `actionlint -ignore 'label "ubuntu-26\.04" is unknown'` passes all remaining checks; no repository lint configuration, action pin or runtime check was weakened. Actual native execution establishes runner-label support independently.

## Candidate result

The corrected implementation head `7402fae6640387ea81de6ad7ef49448a38ba40f7` passed [all three foundation jobs](https://github.com/progentic/Warband/actions/runs/38504739883) and [documentation governance](https://github.com/progentic/Warband/actions/runs/38504739851). The tested PR merge source was `abba9905d64446c7473c39d70041552ee6c66993`; this was not a merge into main.

| Inspected artifact | Ubuntu 24.04 recheck | Ubuntu 26.04 candidate |
|---|---|---|
| Runner image | ubuntu24 / 20261004.327.1 | ubuntu26 / 20260927.149.1 |
| Archive SHA-256 | `bb78a15198c21d5b04da7f6dd67e37c37681ce3a786721c4d98f8c367c6673b3` | `44b49d98b8aa68a1bf7f6d0930c2dec1e1466806183fd902ce54b279233f1d66` |
| Warband SHA-256 | `9d13e9f28ca616e02a18444963831a7ffcc9908c0e59bf598d8c442082c130bd` | `b5c5131b163d7fbdc4f1d008c044781a472c13751336b1f8ecd8dc7884b88088` |
| Existing Python controls | 22 passed | 22 passed |
| Explicit Odin report identities | Two packages / five named tests passed | Identical names/counts passed |
| CLI version/fixture/rejection checks | Passed | Passed |
| ELF format/machine | ELF64 little-endian / machine 62 | Identical |
| Runtime libraries | libc, libm, x64 loader | Same library names; native paths move from `/lib` to `/usr/lib`, with new system revisions |

Downloaded archive digests matched GitHub metadata, and binary SHA-256 values matched manifests. Independent ELF header inspection confirmed x86-64. Both manifests preserve Odin SHA, target, flags and field structure; exact test identities/successes and retained CLI/governance logs were checked. Different toolchain/userspace inputs produce different executable hashes; cross-OS binary byte parity is not claimed. Downloaded binaries were inspected as data, not executed.

The candidate's compiler identity/source guard passed; its report identifies LLVM 19.1.7. Retained compiler metadata identifies ELF64 x86-64 and compiler SHA-256 `d8f32ae713a9ae18d0cdd63db780cdb3db38c08351a78996233c72abffacc32f` (recorded by the runner; the compiler binary itself is not uploaded). Linker inspection reports GNU ld 2.46 as the Clang driver default and Ubuntu LLD 19.1.7 available. Header inspection confirms `/usr/lib/gcc/x86_64-linux-gnu/14` and its C++14 include paths. Package metadata retains filenames, exact versions and SHA-256 values from signed Ubuntu indexes; installed receipts match the selected pins.

### CPU-floor qualification

The candidate's actual ELF GNU property declares x86-64-v3 requirements (ISA-needed mask 7), while both the original v0.0.1 and fresh Ubuntu 24.04 binaries declare baseline only (mask 1). Ubuntu 26.04's selected package filenames also carry `amd64v3`, although dpkg reports architecture `amd64`. This difference was found by inspecting existing artifacts, not by adding tests or changing compiler flags. Native runner success does not establish execution on older generic-x64 hosts. No note stripping, replacement CRT/sysroot, alternate compiler source or production architecture choice is introduced to hide the difference.

### Disposition for owner review

Native Ubuntu 26.04 evaluation passes the requested build, existing behavior and evidence gates. It is ready for owner review as a native CI candidate, with the x86-64-v3 artifact floor explicitly included in the promotion decision. If generic-x64 deployment compatibility is required, this candidate does not establish it. No broader architecture or additional verification is authorized by this result.

Promotion, merge and ADR-0006 acceptance remain blocked on separate owner authorization. The required job still defaults to Ubuntu 24.04 and fails on an unreviewed OS migration. Package retention/recovery and formal ADR ownership remain independent gates. This evidence-only follow-up changes no compiler/profile logic; its own final PR head still requires the existing hosted checks before handoff.

Raw baseline, discovery, failure and successful artifact reviews are retained under `.local/closure-review/ubuntu2604/`; hosted artifacts remain available through the cited runs.
