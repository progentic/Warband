# Phase 1 entrypoint candidate evidence

**Disposition: E1 candidate implemented under explicit owner authorization; formal closure remains pending.** [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) remains Proposed. The [actual effect review](../engineering/phase1-effect-composition-review.md) lists the qualified High graph and every pure/effectful procedure. The older results below belong to their cited pre-E1 heads. They do not certify the new candidate.

## Baseline recheck

The post-merge [foundation run](https://github.com/progentic/Warband/actions/runs/38106636883) and [documentation run](https://github.com/progentic/Warband/actions/runs/38106636905) passed at `06afd20049af0d26a4953d0353da06e623482c8a`. These results belong to the pre-refactor baseline. Main protection and its positive/negative verification remain recorded in [protection evidence](../governance/phase1-protection-proposal.md).

## Historical pre-E1 candidate changes

| Entrypoint | Behavior-tested candidate disposition, not a layer exception |
|---|---|
| Odin CLI | `read_arguments` acquires process arguments; `parse_command` consumes only supplied values; the entrypoint composes acquisition/parsing/presentation. Output streams, command names and exit codes are unchanged. |
| Documentation CLI | Existing three-step `main()` retained. Its cross-layer composition remains an open finding under Option A. |
| Build manifest | Entry composition contains no raw JSON, hashing, subprocess or formatting calls. Technical observation/output helpers and pure frozen-record validation/construction are in separate modules. Format/machine rejection remains before linkage inspection. |

Pure manifest rules have no filesystem, subprocess or environment imports/access. The observations and output manifest are frozen records. Technical collection helpers do not perform architecture acceptance or runner-identity decisions. No runtime authorization, evaluator or state-transition procedure is introduced.

## Historical pre-E1 local results

Native macOS ARM64 verification used the existing source-built Odin at `8b35c86efb78e9ab5223673a07e02fc2a6884191` and exact LLVM/clang 19.1.7. Compiler identity was checked before rebuilding Warband with vet and warnings-as-errors.

| Verification | Observed result |
|---|---|
| Native Warband build and metadata | PASS; ARM64 Mach-O |
| Explicit Odin package/name/report gate | PASS; original two packages / five named tests |
| CLI smoke | PASS; version/fixture output plus missing/unknown/extra argument rejection |
| Python governance/negative controls | PASS; 21 tests, including four new manifest controls |
| Old/new manifest on the same native executable/environment | PASS; complete serialized JSON bytes match the reviewed 06afd20 implementation |
| Actual manifest CLI with hosted mode and missing ImageOS | Rejected as intended; nonzero status and missing-identity error; prior manifest bytes unchanged |
| Exact staged source-only checkout | PASS; documentation and all 21 Python controls without ignored input/toolchain dependencies |
| Workflow/shell/diff inspection | PASS; actionlint, shellcheck and whitespace checks; no workflow or toolchain-lock changes |

The four new controls use supplied observations to verify supported formats and preserved provenance, unsupported format/machine/platform rejection, missing hosted identity rejection without local fallback, and local treatment of stale hosted labels. They do not fabricate source-compiler or executable checks. The old/new comparison exercised the real native compiler/version/linkage/hash acquisition separately from these pure tests.

Native parity JSON and the real rejection log are retained under `.local/closure-review/entrypoint/`. The reviewed diff preserves the constitution, invariant definitions and accepted ADRs byte-for-byte; the pure manifest module imports only dataclasses.

## Historical pre-E1 hosted results

Draft [PR #3](https://github.com/progentic/Warband/pull/3) at head `b87c8be8db7c49fed9707a10e26e6a5f56ddb260` passed its [foundation run](https://github.com/progentic/Warband/actions/runs/38108611919) and [documentation run](https://github.com/progentic/Warband/actions/runs/38108610057). Actions tested PR merge source `d2978ffe504af31a73edc279426378d4d13dc72c` against base `06afd20`; that test merge is not a merge into main.

| Platform | Actual result | Binary SHA-256 |
|---|---|---|
| ubuntu24 / 20261004.327.1, x64 | PASS: pinned source compiler, ELF x86-64, governance, 21 Python controls, original five Odin tests, CLI smoke and artifact upload | `9650cdd2e918c8f0642910e0f1aa6382bc94e55ef8a740c9957f8941ed27a32d` |
| macos15 / 20260907.0337.1, ARM64 | PASS: pinned source compiler, ARM64 Mach-O, governance, 21 Python controls, original five Odin tests, CLI smoke and artifact upload | `436d3e9686776958d00dca787d6f7a98b246ec85076523045e20226f98a529f1` |

All three artifact archives were downloaded and their SHA-256 digests matched GitHub metadata. Platform manifests identified the unchanged Odin SHA and exact LLVM profiles; binary hashes and independently inspected file formats matched the manifests. Source-commit files identified the tested PR merge source. Reports contained the exact original package/test identities and successes, and logs showed all 21 Python controls and CLI smoke passing. Downloaded binaries were inspected as data, not executed. Metadata, archives and the review summary remain under `.local/closure-review/entrypoint/`.

These outcomes are specifically tied to the cited candidate head/test merge. A later documentation update or rule approval is not silently included in that tested commit. No finding is closed from these passes.

## Remaining approval and governance

The owner selected E1 and authorized the candidate implementation and draft-branch publication. E1's qualified High calls resolve the original pure-only reachability contradiction within the listed scope. PR #3 remains draft; all three findings await formal review. Formal ADR acceptance, merge and Phase 1 closure are not inferred from implementation or tests.

Accepted ADRs 0001–0003, constitutional requirements, existing invariant identifiers and WB-NEG-001 through WB-NEG-016 semantics remain unchanged. WB-NEG-017/018 extend foundation build verification only. ADR-0004 ownership/formal acceptance, dependency recovery and ADR-0006 compatibility selection/review remain pending. No Phase 2 code or production architecture is selected.

## E1 local implementation evidence (2026-10-12)

Starting branch/head `phase1-entrypoint-separation` / `028dba1f46085b8052293d3c7c83e77c526b8236` matched the live draft PR #3 head. Main remained `06afd20`. The baseline sources were retained before editing.

The native build used unchanged source-built Odin SHA `8b35c86efb78e9ab5223673a07e02fc2a6884191`, LLVM/clang 19.1.7 and vet/warnings-as-errors. ARM64 Mach-O SHA-256: `f652b9159d86807cffcc7b31f9d7711e57aeacee294dec82042509afaa46a828`. Two Odin packages/five original named tests and CLI smoke passed. All 21 existing Python controls were retained; one bounded structural test includes deliberate effect/upward/raw-API/Mid-call violations (22 total).

Application sources at reviewed `79c2fdf` and starting `028dba1` were identical (the intervening changes were documentation). The saved baseline manifest program and E1 program inspected the same executable/environment independently; complete serialized JSON bytes matched. Real missing hosted ImageOS, unsupported platform and incorrect executable-format invocations failed nonzero without changing existing manifest bytes. Reports, baseline sources, parity JSON and rejection logs are retained under `.local/closure-review/e1/`. A source-only copy, with only an empty `.local` scratch directory for existing tests, passed documentation governance and all 22 controls. actionlint, shellcheck and `git diff --check` passed. These ignored local records are not hosted evidence.

Exact commands:

```sh
export LLVM_CONFIG="$PWD/.local/toolchains/llvm@19/19.1.7/bin/llvm-config"
export CXX="$PWD/.local/toolchains/llvm@19/19.1.7/bin/clang++"
bash scripts/build_warband.sh darwin_arm64
python3 scripts/check_docs.py
python3 -m unittest discover -s tests/governance -v
python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-darwin_arm64/odin --output out/darwin_arm64/tests
python3 scripts/verify_cli.py out/darwin_arm64/warband
actionlint
shellcheck scripts/*.sh
git diff --check
python3 .local/closure-review/e1/verify_regression.py
```

Final hosted candidate results will be tied to an actual pushed head and run; local macOS verification alone is not Linux proof.
