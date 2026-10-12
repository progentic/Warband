# ADR-0007: Phase 1 entrypoint boundaries

- **Status:** Accepted
- **Date:** 2026-10-10
- **Acceptance date:** 2026-10-12
- **Decision:** E1, scoped High effect composition
- **Decision authority:** Project owner, by the supplied acceptance decision
- **Implementation baseline:** [v0.0.0](https://github.com/progentic/Warband/tree/v0.0.0), commit `8afe3512da88fe55e6ca1b919a1bd5d0b931baab`, merged through [PR #3](https://github.com/progentic/Warband/pull/3)
- **Scope:** Phase 1 foundation only
- **Supersedes:** None
- **Related:** ADR-0004, ADR-0005 and ADR-0006 remain Proposed; accepted ADR-0001 through ADR-0003 unchanged

## Decision

Warband adopts E1 for the three existing Phase 1 programs. It preserves High/Mid/Low while permitting narrowly enumerated High procedures to coordinate necessary external effects. It resolves the original effect-composition contradiction without adding a fourth level or changing the meaning of Mid.

1. High coordinates workflows. Only the enumerated Phase 1 High procedures may call related High procedures, pure Mid decisions and reviewed Low technical operations. Other High procedures call pure Mid only.
2. Mid makes decisions using supplied values and calls pure Low helpers only. Every Mid procedure remains transitively pure, including every reachable helper.
3. Low performs narrow technical operations through Low helpers and technical APIs. Low must not call upward, make application policy decisions or independently authorize application behavior.

The [engineering standard](../engineering/coding-standard.md#phase-1-e1-effect-composition) defines the permitted High procedures and dependencies. This is an enumerated exception, not a general change to High authority. The [call/effect review](../engineering/phase1-effect-composition-review.md) maps the reviewed implementation.

## Authorized scope

- `cmd/warband/main.odin`: existing command input, presentation and process termination.
- `scripts/check_docs.py`: documentation acquisition, validation coordination, reporting and exit status.
- `scripts/build_manifest.py`: artifact inspection, build provenance acquisition, validation coordination and publication.

The directly related High subflows listed in the engineering standard are included. New programs, procedures, effects or external dependencies are not automatically covered. Any expansion requires explicit architectural review and project owner authorization before implementation.

## Benefits

E1 separates effect coordination, pure decisions and technical operations. It preserves reusable pure validators, exposes external operations in the reviewed High graph and avoids unnecessary dispatch frameworks or abstraction layers. The implementation retains established CLI behavior, documentation governance, build provenance and architecture validation.

## Tradeoffs

E1 qualifies the original High-to-Mid-only restriction. Eligible High procedures also reach reviewed Low operations, so changes to their graphs or effects require additional review. Maintaining the approved effect list is an ongoing obligation.

Additional High subflows increase code and review volume. They are justified only when they expose a meaningful responsibility or sequence that would otherwise be obscured.

E2 was considered but not selected because it would change Mid purity and permit explicitly effectful Mid compositions. The three-level hierarchy and universal Mid purity remain preferred. The [options comparison](../engineering/phase1-effect-semantics-options.md) is historical context, not additional permission.

## Documented limitations

### 1. Phase 1 only

The exception does not extend to runtime coordination, policy, capabilities, evaluation, state writing, event journals, recovery, replay, model adapters or future execution tools. Those components require independently reviewed authority and effect boundaries. No component inherits E1 permissions merely through procedure names or classifications.

### 2. Bounded structural enforcement

The structural test checks known Python dependencies and representative forbidden patterns. It is not a complete static analyzer and cannot establish whole-program purity or identify every indirect dependency. The Odin graph and technical helper classifications require source review. Passing the test does not replace examining actual dependencies and direct/transitive effects.

### 3. Layering is not a security boundary

High/Mid/Low improves clarity and reviewability. It does not enforce OS permissions, isolate untrusted execution or prevent a compromised native process from accessing resources. Runtime security requires independent authorization, process isolation, resource restrictions, evidence validation and authoritative state ownership.

### 4. Limited build-evidence durability

Invalid inputs are rejected before publication; tested rejection cases preserve the previous manifest. Publication does not guarantee atomic replacement or preservation during interrupted writes, filesystem failures or power loss. No such durability guarantee is claimed. The precise [publication limits](../engineering/phase1-build-and-verification.md#manifest-publication-limits) remain applicable.

### 5. Toolchain paths and provenance

Compiler paths come from the controlled build environment through `LLVM_CONFIG` and `CXX`, not universally hardcoded paths. Existing version, provenance, architecture and dependency validation remains authoritative for supported Phase 1 builds. The manifest collector does not independently establish the supplied executables' provenance; see [toolchain controls](../engineering/phase1-build-and-verification.md#pinned-toolchain).

### 6. Verification must demonstrate value

Additional tests require prior owner review of a concrete failure mode, supporting evidence, existing coverage gap, expected confidence improvement and maintenance cost, as defined in [the test necessity standard](../engineering/coding-standard.md#test-necessity). Passing existing tests does not justify speculative expansion. No new test is required solely to formalize this decision.

## Verification basis

The implementation was merged through PR #3 and published as v0.0.0 at `8afe351`. The [entrypoint evidence](../verification/phase1-entrypoint-evidence.md) records:

- Linux x64 and macOS ARM64 builds.
- 22 Python controls, including bounded structural rejection checks.
- Two Odin test packages and five named tests.
- Deterministic fixtures and CLI smoke checks.
- Manifest parity and pre-publication rejection preservation.
- Documentation governance and required hosted checks.

The baseline's post-merge [Linux/macOS run](https://github.com/progentic/Warband/actions/runs/38281369380) and [documentation run](https://github.com/progentic/Warband/actions/runs/38281369653) passed. These results support implemented Phase 1 behavior and the reviewed procedure graph. They do not establish subsequent runtime security guarantees.

## Acceptance boundaries

Acceptance authorizes no additional implementation. It does not accept ADR-0004, approve ADR-0005 or Phase 2 code, resolve ADR-0006, complete dependency recovery, select production architecture or formally accept the entire Phase 1 milestone.

The three original abstraction findings may be closed separately with references to the reviewed E1 implementation and this formal owner decision. This record does not close them automatically.

## Final disposition

**Accepted:** E1, bounded High effect composition, for the three enumerated Phase 1 programs and approved supporting procedures. Formal acceptance is recorded by applying the project owner's approved governance record.

Future modification requires a specific demonstrated need, impact analysis and project owner authorization. No general exception is implied.
