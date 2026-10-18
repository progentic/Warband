# Native Ubuntu 26.04 compatibility evidence

## Scope and baseline

Owner-selected ADR-0006 Option A is compatibility evaluation only. ADR-0006 remains Proposed. The [owner decisions D1–D5](../engineering/ubuntu2604-promotion-review.md#owner-decision-2026-10-18) record the CI-only floor, authorized checks and post-rollout promotion direction; actual promotion requires its own PR. Production architecture and Phase 2 implementation are not authorized. On 2026-10-18 the owner authorized closing out the evaluation PR through publication. [PR #5](https://github.com/progentic/Warband/pull/5) uses branch `ubuntu-2604-compatibility`, based on v0.0.1 / `3675dca25fd68c867cfb4ed5d9bbcddd545d57aa`. The v0.0.1 baseline tag and default Ubuntu 24.04 profile remain unchanged; publishing this evaluation does not promote the candidate. Reviewers can use the [repository evidence record](https://github.com/progentic/Warband/blob/ubuntu-2604-compatibility/docs/verification/ubuntu2604-compatibility-evidence.md) and the linked hosted runs without a local checkout.

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

Local documentation governance, all 22 Python controls, shellcheck and diff validation passed. Local **actionlint 1.7.12**, installed from Homebrew (built with Go 1.26.3 for darwin/arm64), does not recognize `ubuntu-26.04`: the full run reports that one unknown-label diagnostic. `actionlint -ignore 'label "ubuntu-26\.04" is unknown'` passes all remaining checks; no repository lint configuration, action pin or runtime check was weakened. Actual native execution establishes runner-label support independently.

## Rejecting-control coverage limits

No new rejecting tests were added for `linux_ubuntu2604`. Existing suite success and source review must be reported separately from native-profile fault injection.

| Evidence | Status | Scope |
|---|---|---|
| Existing 22 Python controls | PASS in cited runs | Includes existing default Linux/macOS wrong-patch and malformed-version cases |
| Native 26.04 selected-profile build/version checks | PASS in cited runs | Correct input/profile path only |
| Wrong package/tool version under `linux_ubuntu2604` | NOT RUN | No candidate-specific rejecting case was added |
| Selected profile versus OS mismatch | NOT RUN | Exact OS guard reviewed in source; no new mismatch case executed |
| Unknown/empty explicit profile and cross-platform profile mismatch | SOURCE REVIEW ONLY | Rejecting guards exist; no new fault-injection cases executed |

The native-profile rejecting cases remain an explicit review qualification. They do not inherit PASS from the older default-profile tests. Any proposed additional test requires the owner's five-part necessity review before implementation.

## Release gating

The provisional `0.0.2` entry dated 2026-10-13 was removed during draft review and was not published. On 2026-10-18 the owner authorized closing out PR #5. CHANGELOG now assigns `0.0.2` to publication of the evaluation on 2026-10-18; its version tag is created only after the protected merge succeeds. If publication moves to another date, update the entry to that actual date before merging. This publication authorization does not promote the Ubuntu 26.04 profile or accept ADR-0006.

## Run-to-commit binding for the reviewed report

The report's [foundation run 38505539773](https://github.com/progentic/Warband/actions/runs/38505539773) and [documentation run 38505539866](https://github.com/progentic/Warband/actions/runs/38505539866) both ran at head **`d00b82d78bb3f01622aec8b6a11eaebce929331b`**. Their PR merge source was `4aec10720c02de05f96fbc42f15d67aef2de3d8a`, with parents baseline main `3675dca25fd68c867cfb4ed5d9bbcddd545d57aa` and that exact head. This was a test merge, not publication to main.

| Artifact from those exact runs | Ubuntu 24.04 | Ubuntu 26.04 |
|---|---|---|
| Warband SHA-256 | `5c81a378fe0a2dc7fd41783156834defa496ee539aaa5e1b4fad82a95a971df5` | `3ffdb9d81113101fdd2f06d7e0db17e84ad6b37b52ab790104793d436c545573` |
| Archive SHA-256 | `381323b51bf5399038e92a391e3b25e0a23c657c6a4316cc29c4be61a58688ac` | `f5c420eb8a55e0c323f8afcfb80e032239c1dc8795d3bef66832225882777045` |

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

The candidate's compiler identity/source guard passed; its report identifies LLVM 19.1.7. Retained compiler metadata identifies ELF64 x86-64 and compiler SHA-256 `d8f32ae713a9ae18d0cdd63db780cdb3db38c08351a78996233c72abffacc32f` (recorded by the runner; the compiler binary itself is not uploaded). Linker inspection reports GNU ld 2.46 as the Clang driver default and Ubuntu LLD 19.1.7 available. Header inspection confirms `/usr/lib/gcc/x86_64-linux-gnu/14` and its GCC 14 libstdc++ include paths. Package metadata retains filenames, exact versions and SHA-256 values from signed Ubuntu indexes; installed receipts match the selected pins.

### CPU-floor qualification

The candidate's actual ELF GNU property declares x86-64-v3 requirements (ISA-needed mask 7), while both the original v0.0.1 and fresh Ubuntu 24.04 binaries declare baseline only (mask 1). Ubuntu 26.04's selected package filenames also carry `amd64v3`, although dpkg reports architecture `amd64`. This difference was found by inspecting existing artifacts, not by adding tests or changing compiler flags. Native runner success does not establish execution on older generic-x64 hosts. No note stripping, replacement CRT/sysroot, alternate compiler source or production architecture choice is introduced to hide the difference.

### Identified v3 input source

The [native input inspection run 38507090193](https://github.com/progentic/Warband/actions/runs/38507090193) ran at head **`213f4d4f53ea76c2590adedbc9da78b0636ca033`**, using PR merge source `138aef22493299820d2a4cb7dede940eee67c4c4`. Its [compatibility artifact](https://github.com/progentic/Warband/actions/runs/38507090193/artifacts/11868306785) has SHA-256 `f884f3455b673b0046954235492caba1ff0fc5895ffd0c8e23230faf44bee16c`, independently matched after download. Files `isa-inputs.txt` and `isa-driver.txt` retain object ownership, hashes, GNU notes and dry-run driver selections; `installed-packages.txt` supplies owner-package versions.

| Observed input | Owner/version | ISA-needed declaration |
|---|---|---|
| `/usr/lib/x86_64-linux-gnu/Scrt1.o` (PIE startup) | `libc6-dev:amd64` / `2.43-2ubuntu2.4` | baseline/v2/v3 |
| `/usr/lib/x86_64-linux-gnu/crt1.o` (non-PIE startup) | Same glibc development package | baseline/v2/v3 |
| `crti.o`, `crtn.o` | Same glibc development package | ISA-needed property absent; IBT/SHSTK feature notes present |
| GCC 15 `crtbeginS.o`, `crtendS.o` (default driver selection) | `libgcc-15-dev:amd64` / `15.2.0-16ubuntu1` | ISA-needed property absent |
| GCC 14 `crtbeginS.o`, `crtendS.o` (explicit GCC 14 selection) | `libgcc-14-dev:amd64` / `14.3.0-14ubuntu1` | ISA-needed property absent |
| `/usr/lib/x86_64-linux-gnu/libc.so.6`, `libm.so.6` | `libc6:amd64` / `2.43-2ubuntu2.4` | baseline/v2/v3 |

`Scrt1.o` SHA-256 is `19924e503b1bcb8302a0f34e92ee4b146bec57ba6efa444e017f854c7450a8fe`; `crt1.o` is `d6327b9ec9d9ceb6159e86f42225612cc951800fd8ab38f7e25e986a4e4a825b`.

The Clang 19.1.7 dry-run trace shows `-target-cpu x86-64`, generic tuning and a PIE link using `Scrt1.o`. Default selection uses GCC 15's GCC-owned CRT objects; explicitly selecting GCC 14 changes those objects but resolves the **same glibc startup files**, with the same v3 notes. `ODIN_CLANG_PATH` was unset. The [pinned Odin linker](https://github.com/odin-lang/Odin/blob/8b35c86efb78e9ab5223673a07e02fc2a6884191/src/linker.cpp) uses Clang for the native Linux link. The configured GCC 14 C++ headers apply to building Odin; they do not replace the glibc startup/runtime inputs used by Warband's link.

A concrete source of the executable's v3 declaration is therefore the packaged glibc startup input, independently of GCC 14 header selection. The same native libc/libm also declare a v3 requirement. The driver inspection does not establish that every Odin-generated instruction or other object was audited. It does establish that changing header selection alone cannot remove the selected startup/runtime dependency's floor. This exact native userspace profile carries the constraint; avoiding it would require separately reviewed CRT/runtime inputs or another profile. No alternate userspace, note stripping or build-flag workaround was tested or implemented.

These are read-only input inspections: `clang -###` prints commands without compiling/linking, and `readelf`, ownership queries and hashing inspect existing files. They are not new rejecting tests and do not close the negative-coverage qualifications above.

### Disposition for owner review

Native Ubuntu 26.04 evaluation passes the positive build and existing behavior checks in the cited runs. Owner review must also consider the x86-64-v3 source and the explicitly unexecuted candidate-specific rejecting cases above; this is not a blanket PASS for new-profile negative coverage. If generic-x64 deployment compatibility is required, this candidate does not establish it. No broader architecture or additional verification is authorized by this result.

The evaluation is published as v0.0.2. Proto is the recorded ADR-0006 decision owner, and the review deadline was met on 2026-10-18. D2 authorizes checks A and B in a separate implementation PR; their rejecting evidence is still unexecuted in this record. D3 and D4 set promotion after rollout completion and accept intermittent required-job failures with the Ubuntu 24.04 guard unchanged, including the evidence-preserving manual rerun policy. No promotion, fallback or new rejecting tests are implemented by this documentation update. ADR acceptance, package retention/recovery and ADR-0004 remain open; artifact handling follows D1.

Raw baseline, discovery, failure and successful artifact reviews are retained under `.local/closure-review/ubuntu2604/`; hosted artifacts remain available through the cited runs.
