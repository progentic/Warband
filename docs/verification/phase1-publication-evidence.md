# Phase 1 publication and runner evidence

The user authorized committing and pushing the current Phase 1 status on 2026-10-10 (America/New_York). Foundation commit [53415e7853b598bc341bc651df2edc694b9afe7e](https://github.com/progentic/Warband/commit/53415e7853b598bc341bc651df2edc694b9afe7e) was pushed to `main` without force, retaining the remote initial commit as its parent. The local license matches the remote BSD 3-Clause blob. No account was switched.

## Source review and local verification

The publication inventory contains 92 UTF-8 files. It excludes bootstrap/ZIP inputs, historical planning notes, compiler trees, binaries, logs, caches, and VM state. The review found no symlinks, binary content, or credential-pattern matches in those files. The constitution, invariant definitions, and accepted ADRs 0001–0003 match the retained bootstrap byte-for-byte. This inspection is bounded by the reviewed content and patterns; it is not a general guarantee that future files contain no secrets.

The exact staged source passed documentation governance and 17 Python controls in a source-only copy without the ignored bootstrap or toolchains. The native ARM64 executable was rebuilt using the previously verified Odin source pin and LLVM/clang 19.1.7; architecture, five named Odin tests across two packages, and CLI smoke passed. Actionlint and shellcheck passed. Linux local results remain in [the earlier review](phase1-review-evidence.md).

The README license link exposed a missing LICENSE file in governance fixtures. The fixture now copies the real root license; the two failing positive controls then passed. Markdown hard-break whitespace in the supplied execution directive was replaced with blank paragraphs without changing its instructions.

## First hosted run at 53415e7

| Check | Observed result |
|---|---|
| [Documentation Governance](https://github.com/progentic/Warband/actions/runs/38104508403) | PASS |
| [Phase 1 Linux Foundation](https://github.com/progentic/Warband/actions/runs/38104508390/job/114367030844) | PASS: pinned Odin source build, x64 ELF, governance, 17 Python controls, two packages/five Odin tests, and CLI smoke |
| [Phase 1 macOS Portability](https://github.com/progentic/Warband/actions/runs/38104508390/job/114367031035) | PASS: source-built Odin, ARM64 Mach-O, governance, 17 Python controls, two packages/five Odin tests, and CLI smoke |

All three completed job logs were downloaded and inspected. Linux used the unchanged exact LLVM profile and source pin; its real runner succeeded independently of the local builds. macOS used the ARM64 Sequoia Homebrew LLVM 19.1.7 bottle and explicit keg paths, with minimum macOS version 15.7.9 and the runner's Xcode SDK. Local macOS uses a different reviewed bottle/host version. Neither local binaries nor local compiler caches were uploaded to the runners. The first workflow did not upload artifacts, so its complete binary/manifests/reports are not available as retained artifacts. Job logs remain available subject to GitHub retention.

### Runner findings

The hosted annotations report that the pinned checkout/setup-python actions target Node 20 and are forced to run under Node 24. The newly selected upload-artifact v4.6.2 also declares Node 20 in its reviewed metadata. These source pins were preserved; migration to reviewed native Node 24 action versions remains a dependency maintenance task rather than a hidden substitution.

The Linux runner annotation announces migration of `ubuntu-latest` to Ubuntu 26 beginning 2026-10-19. The current build passed on Ubuntu 24.04. The exact 24.04 guard remains active, so the announced migration is expected to block builds until a reviewed compatible dependency profile is available. Keeping the heavy job on `ubuntu-latest` does not authorize accepting an untested OS or LLVM revision.

Homebrew warned that LLVM 19 was installed but not linked because LLVM 18 was already installed. The workflow selected explicit LLVM 19 keg paths and passed version/identity checks; no global linking change was needed. macOS ARM64 queue-capacity warnings are operational findings, not test results.

## Runner evidence change

The subsequent workflow diff adds explicit bash, stage logs through `tee`, source-commit files, platform summaries, and reviewed SHA-pinned upload-artifact v4.6.2. Uploads run after success or failure, exclude hidden files, fail on missing evidence, and retain only their scoped `out/` directories for 30 days. A local control verified that a producer exiting 7 still exits 7 through `tee` and retains its output; a successful producer remains successful. Actual hosted uploads and their contents remain to be verified.

The runner is an independent verification environment. Differences from local dependencies, architecture, compiler output, and test results are evidence to inspect. This change does not loosen exact version checks, replace failures with local passes, or require platform binaries to have matching hashes. Strict bitwise reproducibility is not claimed.

## Remaining gates

ADR-0004 remains Proposed with an unassigned owner. Required-check enforcement, dependency retention/recovery, and the recorded procedure-layering findings remain open in [the closure plan](../governance/phase1-closure-plan.md). The original WB-CON, WB-INV, and WB-NEG-001 through WB-NEG-012 runtime requirements are still planned/deferred. ADR-0005 is a Proposed design only. Phase 2 implementation and formal Phase 1 acceptance are not authorized by publication.
