# Phase 1 entrypoint candidate evidence

**Disposition: functional candidate verified locally and on hosted runners; rule approval pending.** This record does not close the hierarchy findings or accept ADR-0004/0007. The candidate is scoped by [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md).

## Baseline recheck

The post-merge [foundation run](https://github.com/progentic/Warband/actions/runs/38106636883) and [documentation run](https://github.com/progentic/Warband/actions/runs/38106636905) passed at `06afd20049af0d26a4953d0353da06e623482c8a`. These results belong to the pre-refactor baseline. Main protection and its positive/negative verification remain recorded in [protection evidence](../governance/phase1-protection-proposal.md).

## Candidate changes

| Boundary | Candidate disposition |
|---|---|
| Odin CLI | `read_arguments` acquires process arguments; `parse_command` consumes only supplied values; the entrypoint composes acquisition/parsing/presentation. Output streams, command names and exit codes are unchanged. |
| Documentation CLI | Existing three-step `main()` retained. Its classification awaits approval of the proposed entrypoint rule. |
| Build manifest | Entry composition contains no raw JSON, hashing, subprocess or formatting calls. Technical observation/output helpers and pure frozen-record validation/construction are in separate modules. Format/machine rejection remains before linkage inspection. |

Pure manifest rules have no filesystem, subprocess or environment imports/access. The observations and output manifest are frozen records. Technical collection helpers do not perform architecture acceptance or runner-identity decisions. No runtime authorization, evaluator or state-transition procedure is introduced.

## Actual local results

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

## Actual hosted candidate results

Draft [PR #3](https://github.com/progentic/Warband/pull/3) at head `b87c8be8db7c49fed9707a10e26e6a5f56ddb260` passed its [foundation run](https://github.com/progentic/Warband/actions/runs/38108611919) and [documentation run](https://github.com/progentic/Warband/actions/runs/38108610057). Actions tested PR merge source `d2978ffe504af31a73edc279426378d4d13dc72c` against base `06afd20`; that test merge is not a merge into main.

| Platform | Actual result | Binary SHA-256 |
|---|---|---|
| ubuntu24 / 20261004.327.1, x64 | PASS: pinned source compiler, ELF x86-64, governance, 21 Python controls, original five Odin tests, CLI smoke and artifact upload | `9650cdd2e918c8f0642910e0f1aa6382bc94e55ef8a740c9957f8941ed27a32d` |
| macos15 / 20260907.0337.1, ARM64 | PASS: pinned source compiler, ARM64 Mach-O, governance, 21 Python controls, original five Odin tests, CLI smoke and artifact upload | `436d3e9686776958d00dca787d6f7a98b246ec85076523045e20226f98a529f1` |

All three artifact archives were downloaded and their SHA-256 digests matched GitHub metadata. Platform manifests identified the unchanged Odin SHA and exact LLVM profiles; binary hashes and independently inspected file formats matched the manifests. Source-commit files identified the tested PR merge source. Reports contained the exact original package/test identities and successes, and logs showed all 21 Python controls and CLI smoke passing. Downloaded binaries were inspected as data, not executed. Metadata, archives and the review summary remain under `.local/closure-review/entrypoint/`.

These outcomes are specifically tied to the cited candidate head/test merge. A later documentation update or rule approval is not silently included in that tested commit. No finding is closed from these passes.

## Remaining approval and governance

The proposed rule explicitly excludes policy decisions, runtime evidence evaluation and authoritative transitions from entrypoints. It requires explicit user approval before the three findings can close. Test results are implementation evidence, not that approval.

Accepted ADRs 0001–0003, constitutional requirements, existing invariant identifiers and WB-NEG-001 through WB-NEG-016 semantics remain unchanged. WB-NEG-017/018 extend foundation build verification only. ADR-0004 ownership/formal acceptance, dependency recovery and ADR-0006 compatibility selection/review remain pending. No Phase 2 code or production architecture is selected.
