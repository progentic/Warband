# ADR-0007: Phase 1 entrypoint boundaries

- **Status:** Proposed
- **Date:** 2026-10-10
- **Recorded owner direction:** Option A preserves High/Mid/Low; E1 selected and Phase 1 implementation explicitly authorized by the project owner
- **Implementation record:** 2026-10-12
- **Decision owner:** Unassigned for formal review and acceptance
- **Scope:** Existing Phase 1 CLI, documentation validator and build manifest, including explicitly listed related helpers
- **Supersedes:** None
- **Related:** ADR-0004 (Proposed); accepted ADR-0001 through ADR-0003 unchanged

## Selected effect semantics

E1 gives the three listed Phase 1 High workflows explicit ownership of effect composition. Their permitted calls are related listed High procedures, pure Mid procedures and reviewed Low operations. Other High procedures still call pure Mid only. All Mid procedures remain transitively pure and call pure Low helpers only. Low cannot call upward or make application policy decisions.

The canonical call matrix, eligible High procedure list and permitted Low dependencies are in [the engineering standard](../engineering/coding-standard.md#phase-1-e1-effect-composition). This qualification changes High's original Mid-only restriction in that bounded scope; it neither adds a fourth architectural level nor changes procedure layering into a security boundary.

## Scope and implementation

The eligible programs are `cmd/warband/main.odin`, `scripts/check_docs.py` and `scripts/build_manifest.py`. Only the listed directly related acquisition/publication subflows are included. Permitted effects are process input/exit and stdout/stderr, project documentation observations, and the existing artifact/provenance inspection and manifest output. Fixed inspection commands remain at Low. No generic command dispatch, callback, dependency-injection framework or effect interpreter is introduced.

CLI command parsing and presentation selection are pure decisions over supplied values. Low presentation receives the already selected stream, representation, bytes/text and status; it cannot choose a command or grant execution authority. Documentation status/message selection is pure; reporting only displays the selected result. Pure inventory and manifest coordinators are reused. Manifest acquisition is split into genuine High subflows invoking narrow technical operations; format/machine validation precedes linkage, and complete validation precedes publication.

Module startup only invokes the program's High main. External input/root-path acquisition and output are explicit in the reviewed graph, not hidden in module initialization or lifecycle hooks. Immutable constants and record definitions are not effect composition.

## Benefits and tradeoffs

High owns effect ordering visibly, Mid decisions stay independently testable, and existing pure coordinators remain reusable. The cost is qualified High dependencies, a few necessary observation/publication subflows and ongoing review of the exact scope. A new effect or eligible procedure requires an explicit engineering/decision update and review; a procedure name alone never grants eligibility.

E2 was considered and is not selected. It would permit effectful Mid application composition and Mid-to-Mid calls. E1 instead preserves universal transitive Mid purity. The earlier fourth-level entrypoint proposal and bootstrap/callback workarounds remain rejected. The [comparison](../engineering/phase1-effect-semantics-options.md) is historical decision context, not an operative alternative.

## Verification and limitations

The [actual hierarchy review](../engineering/phase1-effect-composition-review.md) identifies every project procedure and its direct/transitive effects for these programs. One bounded Python dependency control checks pure-module dependencies, Mid's pure-Low calls, raw technical APIs in High and Low upward calls; deliberately invalid examples must fail. Human review remains necessary, including the Odin graph and the meaning of technical representation branches.

Required behavior evidence is unchanged CLI bytes/streams/statuses, phase/document/manifest negative controls, all 21 existing Python tests, both Odin packages/five names, independent same-input manifest byte parity, rejected invocations preserving valid evidence, both executable architectures, applicable lint/diff checks and final hosted checks. The structural control is one additional useful test, not a replacement for those regressions or a general analysis framework.

Procedure hierarchy is code organization and reviewability. It does not grant runtime authority, prove a sandbox or replace OS isolation. Runtime policy, capabilities, evaluation, authoritative state, recovery, replay and model adapters are outside this qualification and remain unimplemented in Phase 1.

## Current status

**E1 implementation is owner-authorized; formal ADR acceptance is not.** PR #3 remains draft. Tests and reviewed implementation evidence support evaluation of the three findings but do not themselves close them, merge the PR or formally accept Phase 1. ADR-0004 ownership, dependency recovery, ADR-0006 compatibility and production architecture remain separate decisions.
