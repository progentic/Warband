# Phase 1 entrypoint candidate evidence

**Disposition: functional candidate verified locally; rule approval pending.** This record does not close the hierarchy findings or accept ADR-0004/0007. The candidate is scoped by [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md).

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

Native parity JSON and the real rejection log are retained under `.local/closure-review/entrypoint/`. The reviewed diff preserves the constitution, invariant definitions and accepted ADRs byte-for-byte; the pure manifest module imports only dataclasses. Linux x64 and macOS ARM64 hosted candidate checks and their artifacts still need recorded outcomes. Do not substitute the passing baseline runs for the candidate.

## Remaining approval and governance

The proposed rule explicitly excludes policy decisions, runtime evidence evaluation and authoritative transitions from entrypoints. It requires explicit user approval before the three findings can close. Test results are implementation evidence, not that approval.

Accepted ADRs 0001–0003, constitutional requirements, existing invariant identifiers and WB-NEG-001 through WB-NEG-016 semantics remain unchanged. WB-NEG-017/018 extend foundation build verification only. ADR-0004 ownership/formal acceptance, dependency recovery and ADR-0006 compatibility selection/review remain pending. No Phase 2 code or production architecture is selected.
