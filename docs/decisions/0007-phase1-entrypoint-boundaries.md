# ADR-0007: Phase 1 entrypoint boundaries

- **Status:** Proposed
- **Date:** 2026-10-10
- **Recorded owner direction:** 2026-10-11: select Option A, preserve Warband's existing three-level procedure hierarchy
- **Decision owner:** Unassigned for formal ADR review and acceptance
- **Previous proposal:** Additional entrypoint `Boundary` classification not approved
- **Scope:** Existing Phase 1 CLI, documentation validator, and build manifest only
- **Supersedes:** None
- **Related:** ADR-0004 (Proposed); accepted ADR-0001 through ADR-0003 unchanged

## Decision direction and limits

The project owner has selected **Option A: preserve the existing High/Mid/Low hierarchy**. The earlier proposal to classify entrypoints as a fourth, exempt `Boundary` level is **not selected**. Its passing candidate tests are evidence of behavior, not approval of an architecture exception.

Retain the existing requirements under review:

- **High:** coordinate the prescribed workflow; call Mid procedures only.
- **Mid:** apply rules to supplied values, remain pure, and call only permitted Low helpers.
- **Low:** implement narrowly scoped technical operations and primitives, without calling upward or making policy decisions.

Do not silently reclassify a High procedure as an entrypoint exception, label effectful I/O as pure, rename a call to hide the same dependency, or weaken the rule to make the current code compliant. These constraints also do not create new runtime privileges or trust boundaries.

The literal rules expose an **unresolved effect-composition problem**: an executable must acquire input and produce output, yet a strictly pure Mid procedure cannot perform I/O, High cannot directly call Low, and Low cannot coordinate upward. Record a concrete legal call graph before claiming compliance. If no compliant arrangement is possible under the existing rules, report that incompatibility for owner review rather than inventing a fourth level or introducing unapproved exceptions.

This records the chosen direction, **not** a formal acceptance of ADR-0007 or a solution to the remaining call-graph conflict.

## Options and tradeoffs considered

| Option | Benefit | Cost or constraint | Disposition |
|---|---|---|---|
| **A. Preserve strict High/Mid/Low** | Consistent abstraction contract; predictable direction of dependencies; less opportunity for an exception to spread into security authority code | Can require extra, potentially mechanical wrappers; effect composition is currently underspecified; review and implementation may take longer | **Selected by project owner** |
| **B. General effectful entrypoint adapter** | Small, readable glue code; matches the verified PR #3 candidate with minimal change | Creates an additional classification that can weaken the literal hierarchy or expand to runtime coordinators if interpreted broadly | Not selected |
| **C. Tightly constrained entrypoint exception** | Limits effectful composition more than B; potentially reduces wrapper overhead | Still changes the three-level contract; requires new scope and enforcement rules; extra design without advancing the harness's first authority proof | Not selected |

Option A's consistency benefit is real, but so is its potential for unnecessary ceremony. The objective is a reviewable, working harness, **not** maximizing the number of layers, helpers, tests, or documents. Do not introduce generic dispatchers, dependency-injection frameworks, extra abstractions, or broad architectural reform solely to satisfy this Phase 1 correction.

## Existing findings and PR #3 impact

Three published baseline findings remain open:

1. `cmd/warband/main.odin`: executable argument acquisition and parsing were coupled.
2. `scripts/check_docs.py`: `main()` sequences inventory, validation, and reporting across technical and decision work.
3. `scripts/build_manifest.py`: `main()` mixed inspection, JSON parsing, hashing, validation, and manifest construction.

Draft [PR #3](https://github.com/progentic/Warband/pull/3) has useful candidate improvements: supplied-value Odin parsing, pure manifest rules, independent manifest I/O, four additional Python controls, and successful hosted verification. These changes may be retained **only where they comply with the selected hierarchy**. The PR's proposed fourth-level entrypoint wording in `docs/engineering/coding-standard.md`, and any findings closed solely through that wording, are **not approved**.

This ADR revision changes no application code or procedure classifications. PR #3 stays draft; no merge, finding closure, ADR acceptance, or Phase 2 implementation is authorized by this note.

## Required next review, strictly within Phase 1

Before advancing the entrypoint correction, require a focused proposal that:

1. Maps actual calls and side effects for the **three named entrypoints only**, using High/Mid/Low classifications and the unchanged allowed-call rules.
2. Explains how input acquisition, pure decisions, and output occur without hidden upward calls or falsely pure wrappers. If the requirements cannot all hold, explicitly state the contradiction and the smallest decision needed; stop rather than widen scope.
3. Reuses existing procedures where valid. Adds only necessary code to correct a demonstrated mismatch. Does not implement a generic orchestration framework.
4. Preserves CLI output and exit statuses, documentation findings, manifest fields and byte parity, artifact verification order, exact compiler and dependency pins, and the current negative controls.
5. Reruns the complete applicable governance and hosted verification gates on the revised candidate. Passing tests do not by themselves prove structural compliance.

The scope is **Phase 1 foundation composition**. This record does not alter the runtime constitution, accepted ADRs, capability/policy/evidence/state boundaries, event encoding, execution recovery, or replay. ADR-0004 ownership, dependency retention, and ADR-0006 hosted-runner compatibility remain independent review items.

## Status

**Option A is selected as the owner's direction. ADR-0007 remains Proposed.** The legal entrypoint/effect call graph is unresolved; all three architecture findings remain open pending evidence and formal review. Earlier hosted PR #3 checks support only the tested candidate's behavior, not compliance with this selected rule.
