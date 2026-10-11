# Phase 1 verification review

**Verdict: locally verified foundation; formal Phase 1 acceptance remains BLOCKED.** The Linux package/version conflict is corrected and tested on Ubuntu 24.04 x64. Native macOS ARM64 checks also pass independently. ADR-0004 remains Proposed with an unassigned owner. No hosted Actions execution is claimed.

This review supersedes the initial implementation's shared LLVM 19.1.7 assumption and its unverified Linux disposition. Verification occurred on 2026-10-10. No Phase 2 implementation was added.

## Corrections and changed files

| File | Correction |
|---|---|
| `toolchain/odin.lock.json` | Separates exact Linux LLVM/clang 19.1.1 from macOS 19.1.7; pins Linux LLVM package revision. |
| `scripts/toolchain_versions.py` | Separates pure exact-version decisions from JSON, executable-output, regex, and display wrappers. |
| `scripts/install_linux_toolchain.sh` | Requires Ubuntu 24.04 and exact Debian LLVM package revision; records package URIs/revisions; fails partial apt index updates. |
| `scripts/build_odin.sh` | Reads the selected platform profile and uses the shared exact-version gate. |
| `scripts/prepare_macos_llvm.py` | Reads the unchanged native bottle version from the macOS profile. |
| `scripts/build_warband.sh` | Adds the selected LLVM bin directory to PATH so Odin resolves its matching clang linker. |
| `scripts/run_odin_tests.py` | Sets child PATH and ODIN_ROOT for the selected source compiler/resource tree and linker. |
| `.github/workflows/phase1.yml` | Preserves ubuntu-latest, safe triggers, pinned actions and read-only permissions; carries the macOS LLVM location into the separate test step. |
| `tests/governance/test_governance.py` | Builds fixtures from tracked documents instead of the ignored bootstrap input absent in a fresh checkout. |
| `tests/governance/test_toolchain_versions.py` | Executes the wired version gate against exact valid, wrong-patch, and malformed tool-output cases. |
| `docs/verification/phase1-fixture-specification.md` | Independently defines the 25-byte fixture layout and explains the static expected bytes. |
| `tests/fixtures/phase1.golden.hex` | Stores the literal golden sequence, independently checked using Python struct. |
| `tests/odin/foundation/foundation_test.odin` | References the independent specification; retains literal expected bytes and the same five-test inventory. |
| `vm/x64-review.yaml`, `vm/x64-review-selection.json` | Add a checksum-reviewed, project-scoped x64 development verification guest without selecting production architecture. |
| `vm/README.md` | Records transport, scope, image and cleanup details for local verification. |
| `docs/decisions/0004-reproducible-odin-toolchain-and-ci.md` | Adds a Proposed correction; neither owner nor status is promoted. |
| `docs/engineering/phase1-build-and-verification.md` | Updates platform pins and linker/resource configuration. |
| `docs/verification/traceability-matrix.md` | Maps completed local foundation proofs and leaves runtime invariants planned/deferred. |
| `docs/verification/phase1-evidence.md` | Marks the first handoff as historical and points to this correction. |

The constitution, invariant definitions, accepted ADRs 0001–0003, and original WB-NEG-001 through WB-NEG-012 semantics are preserved. No remotes, account switch, commit, push, provider credentials, production deployment, or runtime acceptance pipeline were introduced.

## Exact inputs and platform proofs

Both source builds use official Odin SHA `8b35c86efb78e9ab5223673a07e02fc2a6884191` and the previously reviewed build-script checksum. HEAD, clean source, compiler version/PATH and resource directories were verified.

| Platform | Real dependency versions | Artifact and result |
|---|---|---|
| Ubuntu 24.04.5 x64, full QEMU guest | LLVM/clang 19.1.1; clang-19, llvm-19-dev, lld-19 at `1:19.1.1-1ubuntu1~24.04.2`; GCC 14 headers `14.2.0-4ubuntu2~24.04.1`; make `4.3-4.1build2` | PASS: source-built Odin, Warband build, ELF64 x86-64 identity, vet, tests and smoke |
| Native macOS 27.0.1 ARM64 | LLVM/clang 19.1.7 from the reviewed Homebrew bottle | PASS: source-built Odin, Warband build, ARM64 Mach-O identity, vet, tests and smoke |

Native ARM64 Warband SHA-256: `0a7ba85abdceef97e9e47a4f903403f33f9c12aa198df4de942b6770111be29c`.

Linux Warband SHA-256: `52f8ca05269611b5db8361f9816f87a43194067f21c77528f7af50ecc02bde33`. `readelf` reports ELF64, little-endian, Advanced Micro Devices X86-64. Linkage is Linux libm/libc plus the x64 ELF interpreter. Linux files, build manifest, dependency receipts and JSON reports are retained under `out/linux_amd64/`; native results remain under `out/darwin_arm64/`. Raw command logs are under `.local/review/`.

The verification VM used Canonical's Ubuntu 24.04 image release 20260926 with SHA-256 `6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2`, verified before provisioning. Its state is under `.local/lima/`; it has no host mounts, guest agent, container runtime, or application port forwarding. SSH management binds only to localhost. This x64 development selection does not select production architecture. The earlier ARM profile remains unprovisioned.

## Commands and observed outcomes

Linux commands ran inside the guest source copy at `/home/godzilla.guest/warband`, with LLVM_CONFIG `/usr/bin/llvm-config-19`, CXX `/usr/bin/clang++-19`, and CXXFLAGS selecting GCC 14 headers. The same committed-intended scripts are used by the CI definition; nothing was committed during this task.

| Command | Actual result |
|---|---|
| `bash scripts/install_linux_toolchain.sh` | PASS after local transport setup: signed Ubuntu packages installed at the locked revision; actual LLVM/clang 19.1.1 verified. |
| `bash scripts/build_odin.sh linux_amd64` | PASS: release compiler built from the exact upstream source, with source and compiler identity checks. |
| `bash scripts/build_warband.sh linux_amd64` | PASS: x64 ELF with vet/warnings-as-errors and manifest generated. |
| `python3 scripts/check_docs.py` | PASS on Linux and macOS. |
| `python3 -m unittest discover -s tests/governance -v` | PASS: 17 tests on Linux and macOS; includes phase, document, inventory, and exact toolchain rejection controls. |
| `python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-linux_amd64/odin --output out/linux_amd64/tests` | PASS: 2 packages / 5 named tests; fresh JSON reports and exact counts/success flags checked. |
| `python3 scripts/verify_cli.py out/linux_amd64/warband` | PASS: version/fixture output and missing/unknown/extra argument rejection. |
| `file out/linux_amd64/warband` and `readelf -h out/linux_amd64/warband` | PASS: independently inspected ELF64 x86-64 identity. |
| `bash scripts/build_odin.sh darwin_arm64` | PASS with the independent native 19.1.7 pin. |
| `bash scripts/build_warband.sh darwin_arm64` | PASS: ARM64 Mach-O and manifest. |
| `python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-darwin_arm64/odin --output out/darwin_arm64/tests` | PASS: the same five named tests independently on native ARM64. |
| `python3 scripts/verify_cli.py out/darwin_arm64/warband` | PASS: native executable behavior. |
| `python3 -m unittest discover -s .local/review/ci-checkout/tests/governance -v` | PASS: 17 controls in a source-only checkout simulation without the ignored bootstrap or native toolchains. |
| `actionlint .github/workflows/docs.yml .github/workflows/phase1.yml` | PASS: actual checked-in-intended workflow YAML, action inputs and embedded shell reviewed. |
| `shellcheck scripts/install_linux_toolchain.sh scripts/build_odin.sh scripts/build_warband.sh vm/validate.sh` | PASS: no findings. |

The independent golden reference is `struct.pack('<BQQQ', 1, 0x0102030405060708, 2, 3)` compared to the static hex sequence. It passed on both platforms without calling or importing Warband's encoder. The Odin golden test also retains its literal expected array; round-trip behavior is supplemental.

## Negative controls and corrections discovered by real execution

All phase, mandatory-document, link, guidance, symlink, manifest omission/deletion, zero/wrong-count, unsuccessful report, and wrong-patch/malformed version controls fail as intended inside their passing test cases. No version check was weakened to accept any LLVM 19 release.

Two additional CI blockers were fixed: fixtures depended on an ignored input tree, and versioned clang packages did not supply the generic clang name on the build/test PATH. The fresh-checkout simulation and real Linux link/tests now prove those corrections.

Initial guest network attempts failed to reach Ubuntu directly. Local verification used a temporary loopback-only relay from guest repository requests to Canonical HTTPS archives, preserving `/usr/share/keyrings/ubuntu-archive-keyring.gpg`, signed index validation and package hashes. Receipts record the local transport URL; relay logs show the Canonical upstream route. The relay is not a checked-in CI dependency or a runtime adapter. Hosted jobs use their normal signed Ubuntu repository transport.

Source-only transfer also exposed macOS metadata sidecars and an overly broad archive exclusion. Source identity/clean-tree checks rejected them before compilation. The missing tracked source was restored from the pinned Git objects and transport metadata removed. No source-check failure was ignored, and no native executable or object was reused in the Linux build.

## Current disposition

| Gate | Result |
|---|---|
| Exact Linux dependency correction and real x64 build/test/architecture/manifest | PASS locally |
| Independent native ARM64 build/tests and portable golden | PASS locally |
| Governance and test completeness rejection controls | PASS locally, including fresh-checkout simulation |
| Workflow syntax, least privilege, exact action pins, ubuntu-latest placement | PASS local inspection |
| Actual hosted CI execution and branch enforcement | Pending: publication authorized after this review; actual workflow results and enforcement remain unverified; see the [closure plan](../governance/phase1-closure-plan.md) |
| Foundation traceability and preserved runtime invariants | PASS; Phase 2 properties remain unimplemented |
| ADR ownership and formal acceptance | BLOCKED: owner unassigned, ADR-0004 Proposed |

The foundation now has real local Linux and macOS evidence. Formal Phase 1 completion is not declared. ADR-0005 remains the next design milestone after the remaining governance gates; canonical runtime event encoding, transactional acceptance, recovery dispositions and deterministic replay are not implemented here.

## Cleanup

The temporary loopback relay was terminated. Standard Canonical repository URLs were restored in the guest after evidence collection, and the x64 verification VM was stopped. Its recoverable project-scoped disk/config and verified image remain under `.local/`; build outputs remain ignored. No persistent host listener or production service was left running.
