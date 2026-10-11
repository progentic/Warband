# Phase 1 verification evidence

This is the initial implementation record. The later [verification review](phase1-review-evidence.md) supersedes its Linux pin and platform/gate status. The original combined 19.1.7 assumption was incorrect for Ubuntu Noble.

Phase 1 foundation code and local verification are present. Formal completion is **BLOCKED**: ADR-0004 remains Proposed, the decision owner is unassigned, Linux execution is unverified, the development VM image is unselected, and no GitHub remote or Actions run is authorized. No Phase 2 execution or authoritative acceptance was implemented.

Verification date: 2026-10-10. Host: Apple Silicon macOS 27.0.1. Python: 3.14.8. The implementation follows the supplied directive; the original bootstrap remains a local immutable reference.

## Changed files

The 52 baseline files were imported at the repository root after comparison, without conflicting overwrite. The following paths contain meaningful Phase 1 additions or changes; inherited documents not listed retain their baseline text.

| Path | Change |
|---|---|
| `AGENTS.md` | Records local Phase 1 authorization and continued remote/commit/Phase 2 restrictions. |
| `README.md` | Describes the actual CLI and outstanding completion gates. |
| `SECURITY.md` | Corrects repository status without weakening security rules. |
| `CHANGELOG.md` | Records foundation additions and incomplete Linux/cloud/governance gates. |
| `.gitignore` | Excludes generated toolchains, VM state, outputs, interpreter caches, ZIP inputs, and the retained bootstrap. |
| `project.json` | Declares validated Phase 1 as an integer. |
| `docs/decisions/0004-reproducible-odin-toolchain-and-ci.md` | Retains the supplied ADR byte-for-byte as Proposed, with unassigned ownership. |
| `docs/engineering/phase1-agent-execution-directive.md` | Retains the supplied execution authorization. |
| `toolchain/odin.lock.json` | Pins the official source commit, reviewed build-script hash, LLVM/C++ inputs, and macOS bottle checksum. |
| `scripts/build_odin.sh` | Builds exact source, verifies dependencies/tree/version/resources, and records compiler inputs. |
| `scripts/install_linux_toolchain.sh` | Resolves and installs exact signed-repository package candidates and checks LLVM/clang 19.1.7. |
| `scripts/prepare_macos_llvm.py` | Verifies and stages the bottle, relocates local LLVM, and signs changed local binaries. |
| `scripts/assert_toolchain.py` | Rejects wrong source revision, PATH compiler, version, or resource root. |
| `scripts/build_warband.sh` | Builds the explicit command package into a platform-specific directory. |
| `scripts/build_manifest.py` | Checks executable identity and records actual build provenance/linkage/checksum. |
| `cmd/warband/main.odin` | Provides version/fixture commands and safe rejection of unsupported arguments. |
| `src/domain/types.odin` | Defines distinct IDs/tick/schema, typed errors, and pure fixture validation. |
| `src/fixture/codec.odin` | Encodes/decodes bounded portable fixture bytes through narrow endian wrappers. |
| `scripts/check_docs.py` | Coordinates inventory loading, pure validation, and reporting. |
| `scripts/governance.py` | Holds immutable document records and pure phase/governance rules with named finding codes. |
| `scripts/document_io.py` | Separates filesystem access, parsing, and report presentation from document rules. |
| `tests/governance/test_governance.py` | Mutates real fixtures to verify phase and preserved governance rejection paths. |
| `scripts/test_inventory.py` | Rejects incomplete manifests and false-success compiler reports. |
| `scripts/run_odin_tests.py` | Discovers all Odin test packages, runs each declared package, and checks exact JSON report names/counts. |
| `tests/odin-packages.json` | Enumerates the two actual packages and five named tests. |
| `tests/governance/test_test_inventory.py` | Proves omission, deletion, wrong counts, and failed reports cannot pass. |
| `tests/odin/foundation/foundation_test.odin` | Checks golden bytes, injected values, round trip, and compile-time ID distinction. |
| `tests/odin/negative/negative_test.odin` | Rejects unknown fixture schema, empty IDs, and invalid byte lengths. |
| `scripts/verify_cli.py` | Independently checks output and three rejected argument forms on the built executable. |
| `.github/workflows/docs.yml` | Preserves the validate job while pinning actions and removing credential persistence. |
| `.github/workflows/phase1.yml` | Defines ordered Linux compiler/build/governance/test/smoke gates and separate macOS portability validation. |
| `vm/lima.yaml` | Prepares a development ARM64 VZ profile with no image, mounts, container runtime, or application forwarding. |
| `vm/selection.json` | Keeps image URL/digest and production architecture unset. |
| `vm/validate.sh` | Scopes validation state to this project without exposing provisioning. |
| `vm/README.md` | Documents the exact image/provisioning block and mount/state constraints. |
| `docs/engineering/phase1-build-and-verification.md` | Provides reproducible commands and precise proof limits. |
| `docs/engineering/coding-standard.md` | Separates pure domain rules from effectful boundary adapters and keeps the layering decision open. |
| `docs/engineering/package-boundaries.md` | Maps implemented foundation packages and deferred gateway/recovery ownership. |
| `docs/architecture/dependency-rules.md` | Documents actual foundation dependencies. |
| `docs/architecture/execution-pipeline.md` | Marks the execution pipeline and unresolved authority decisions deferred. |
| `docs/contracts/model-proposals.md` | Distinguishes fixture checks from unimplemented proposal/audit obligations. |
| `docs/verification/negative-path-catalog.md` | Adds WB-NEG-013 through WB-NEG-016 without changing previous identifiers. |
| `docs/verification/traceability-matrix.md` | Maps foundation evidence and leaves every runtime invariant deferred. |
| `docs/verification/phase1-evidence.md` | Records commands, observed results, corrections, and blocked acceptance gates. |

## Toolchain and artifact results

- Official Odin source: `8b35c86efb78e9ab5223673a07e02fc2a6884191`.
- Reviewed source change: two added lines and one removed line in `src/check_expr.cpp` fixing array-of-any assignment handling. Build script and Makefile were inspected at that full revision.
- Reviewed upstream build-script SHA-256: `d55a0cc0ac702a8697bbfe048966fa7d4f74377ce5c7f66bd853fce1cf1de206`.
- Compiler reports `dev-2026-10:8b35c86`; checked source HEAD matches the full pin.
- Native LLVM and Homebrew clang: **19.1.7**; Homebrew zstd dependency: **1.5.7_1**; native GNU Make: **3.81**.
- Homebrew bottle SHA-256: `cd9291ec597cc0e14dc423523dde71c1f3d65ab9359d92fcaa0d91d9059432d5`, independently matched before preparation.
- Native compiler build uses `make release` and `-mmacosx-version-min=27.0.1`, matching the local SDK/dependency host. It does not claim compatibility with older macOS hosts.
- Warband artifact: `out/darwin_arm64/warband`, **Mach-O 64-bit executable arm64**.
- Artifact SHA-256: `b602324f49ed1631576a0612262d0841b2dc390d9ea751621be35d87ac80a2ca`.
- Observed Warband linkage: `/usr/lib/libSystem.B.dylib`.
- Full local compiler/build metadata and JSON test reports are generated under `out/darwin_arm64/`; raw verification logs are under `.local/evidence/`. These files are deliberately ignored by Git. No x64 ELF artifact exists.

## Commands and actual outcomes

Native build commands below used project-local `LLVM_CONFIG`, `CXX`, `PATH`, and `ODIN_ROOT` from the [build guide](../engineering/phase1-build-and-verification.md).

| Command | Actual outcome |
|---|---|
| `python3 warband-docs-bootstrap-v2/scripts/check_docs.py` | PASS: unchanged baseline validated before import. |
| `python3 scripts/prepare_macos_llvm.py` | PASS after staging fix: verified bottle, LLVM 19.1.7, existing zstd 1.5.7_1. |
| `bash scripts/build_odin.sh darwin_arm64` | PASS: source compiler built with clang/LLVM 19.1.7 and full revision identity asserted. |
| `bash scripts/build_warband.sh darwin_arm64` | PASS: odin build with vet/warnings-as-errors and ARM64 Mach-O assertion. |
| `python3 scripts/check_docs.py` | PASS: updated Phase 1 governance validation. |
| `python3 -m unittest discover -s tests/governance -v` | PASS: **15 tests**, including real document mutation and manifest/report negative controls. |
| `python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-darwin_arm64/odin --output out/darwin_arm64/tests` | PASS: **2 packages / 5 tests**, exact names/counts and all success flags checked. |
| `python3 scripts/verify_cli.py out/darwin_arm64/warband` | PASS: version and fixture output plus missing/unknown/extra-argument rejection. |
| `actionlint .github/workflows/docs.yml .github/workflows/phase1.yml` | PASS: YAML/workflow/action-input and embedded shell inspection. |
| `shellcheck scripts/build_odin.sh scripts/build_warband.sh scripts/install_linux_toolchain.sh vm/validate.sh` | PASS: no findings. |
| `bash -n scripts/build_odin.sh scripts/build_warband.sh scripts/install_linux_toolchain.sh vm/validate.sh` | PASS: shell syntax. |
| `env -u ImageOS -u ImageVersion GITHUB_ACTIONS=true LLVM_CONFIG="$PWD/.local/toolchains/llvm@19/19.1.7/bin/llvm-config" CXX="$PWD/.local/toolchains/llvm@19/19.1.7/bin/clang++" python3 scripts/build_manifest.py darwin_arm64` | Expected failure, exit 1: simulated hosted context without image identity is rejected. This does not represent a cloud run. |
| `python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-darwin_arm64/odin --output out/darwin_arm64/negative-control --manifest .local/inputs/omitted-package.json` | Expected failure, exit 1: omitted package rejected before test execution. This is a passing negative control. |
| `bash vm/validate.sh` | Expected block, exit 1: Lima reports `field images must be set`; no VM created. Sandbox also denies Rosetta sysctl detection, producing a warning. |

### Explicit Odin inventory

| Package | Named tests observed successful |
|---|---|
| `tests/odin/foundation` | `fixture_has_exact_portable_bytes`, `fixture_round_trip_preserves_injected_values` |
| `tests/odin/negative` | `unknown_fixture_schema_is_rejected`, `empty_identifiers_are_rejected`, `truncated_and_oversized_bytes_are_rejected` |

The foundation package also compiles assertions distinguishing TaskId from RunId and Tick. No absent Phase 2 invariant, integration, or replay suite is labeled passing.

## Security and governance preservation

The constitution, constitutional-invariant document, and accepted ADR-0001 through ADR-0003 compare byte-for-byte with the original. The 52-file retained bootstrap compares byte-for-byte with its ZIP. Supplied ADR-0004 compares byte-for-byte with its attachment and remains Proposed. WB-NEG-001 through WB-NEG-012 retain their original meaning and remain deferred.

All required baseline checks remain, with explicit phase validation replacing only the blanket source-directory prohibition. Mandatory contract/decision/invariant documents are also checked for presence; symlinked input and nested override hiding are rejected. Every gate failure remains nonzero.

The CLI cannot execute tools or mutate authoritative state. Policy, capability, approval, evidence, event persistence, authoritative acceptance, sandbox, recovery, replay, providers, and learning remain unimplemented. The foundation fixture is not a settled runtime event serialization format. Broad procedure layering/effect dispatch, integrity anchoring, and transactional recovery remain open decisions.

## Diff review and corrections

No commits exist, so review used file comparison with the immutable bootstrap, complete new-code inspection, compiler/vet output, actionlint, shellcheck, and fixture controls. No files were staged or committed. The root Git top level was checked before repository operations; remotes remain empty.

Corrections made during implementation:

- Replaced nonexistent endian API spellings with the actual checked get/put API and narrow technical wrappers.
- Corrected the CLI exit wrapper from i32 to the OS API's int type; rebuilt and reran verification afterward.
- Fixed masked source-status failures caused by absent git-lfs; source commands now use per-command filter overrides, capture errors directly, and reject changed/untracked source.
- Replaced workflow export-with-command-substitution forms that shellcheck flagged for masking failures.
- Restricted ignored-directory exclusions to the repository root; an override under `docs/build/` now fails validation.
- Changed test discovery to scan all Odin files, so nonstandard filenames cannot hide a package.
- Fixed repeated extraction of read-only bottle files by staging before replacement; reran the actual preparation successfully.
- Matched the native compiler deployment target to the local macOS dependency/SDK version after a linker warning; the final source build reports no older-platform compatibility claim.

Review found no placeholder tests, disabled verification, broad GITHUB_TOKEN permissions, credential persistence, privileged PR checkout trigger, home mount, public application forwarding, deployment action, provider secret, or Phase 2 execution implementation. Temporary anonymous GHCR pull-token metadata was removed. All meaningful final code changes were verified after correction.

## Acceptance gates

| ADR-0004 acceptance criterion | Outcome | Evidence or remaining prerequisite |
|---|---|---|
| Baseline comparison/import and Proposed decision | PASS | Original 52 files and protected documents preserved; supplied ADR unchanged. |
| Phase-aware governance with retained restrictions | PASS | Real fixture tests, malformed/unknown phase controls, mandatory-document rejection. |
| Pinned toolchain inputs and identity | PASS for files/local build; commit BLOCKED | Full SHA/hash and LLVM/C++ 19.1.7 verified; files stay uncommitted because commits are prohibited. |
| Clean Linux x64 compiler/application build and ELF | BLOCKED | No selected/provisioned local Linux guest and no authorized remote Actions run. Native Mac results do not satisfy this gate. |
| Explicit manifest and failure controls | PASS locally | Two packages, five named successes, omission/deletion/count/failure controls. |
| Stable least-privilege Linux CI definition | PASS for definition | ubuntu-latest, immutable action SHAs, safe triggers, read-only token, credential-free checkout; no cloud execution/enforcement claimed. |
| macOS portability verification | PASS locally | ARM64 source-built compiler, CLI/vet, five Odin tests and smoke checks. CI macOS job not executed. |
| Project-scoped Lima preparation | PASS for prepared profile; runnable VM BLOCKED | ARM64 development profile and scoped validation wrapper; reviewed image URL/digest still unset. |
| Documentation and traceability | PASS for local implementation | Foundation mappings added; all runtime constitutional guarantees deferred. |
| Recorded evidence and known gaps | PASS | Actual commands, versions, architecture, counts, corrections, and partial statuses recorded here. |
| Responsible owner and formal governance gate | BLOCKED | Owner unassigned; ADR-0004 Proposed; no formal governance approval. |

**Gate outcome: formal Phase 1 completion remains BLOCKED.** Next prerequisites are governance ownership/review, a reviewed development image and digest for Linux verification, and separately authorized repository/Actions configuration if cloud evidence is desired. The production architecture remains unset. No remote configuration, account switch, commit, push, deployment, or credential provisioning occurred.
