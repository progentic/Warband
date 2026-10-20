# Phase 2 entry review

- **Status:** Design preparation; implementation blocked on the decisions below
- **Owner:** Proto, assigned to ADR-0005 on 2026-10-18
- **Reviewed source baseline:** `ccba4b68a959bacbfed1cdff40dcb109b8acaa9d`, merged PR #8
- **Implementation phase:** `project.json` remains Phase 1

## Boundary to prove

The next deliverable is a deterministic no-op authority path. A proposal receives a policy decision and bounded capability, produces independently evaluated evidence, and results in at most one accepted transition. Recovery and replay use recorded history. This is the Phase 2 outcome in the [phase plan](../governance/PHASE_PLAN.md#phase-2-deterministic-authority-core), not an implementation claim.

The governance review is **conditionally aligned**: preparation can proceed, but the current Proposed [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md) leaves material inputs undefined. Its verification matrix already identifies the affected WB-CON-001 through WB-CON-009, WB-INV and WB-NEG requirements; this review does not duplicate or change those identifiers.

## Decisions required before implementation

| Decision | Current evidence or gap | Required owner disposition |
|---|---|---|
| Canonical event and payload specification | ADR-0005 proposes field order but leaves widths, limits, genesis, time representation and complete payload schemas open | Review exact wire tables, proposal fingerprint input, producer registry and independent golden vectors |
| Store and durability | Selected SQLite direction now proposes WAL/FULL, a writer gate across prepare/commit/confirm and checkpoint-confirmed read visibility; exact dependency and storage profile remains open | Review constraints, locking and target flush assumptions; macOS development establishes no durability claim |
| Protected-head custody | Separate same-VM identity; draft local peer-credential protocol, distinct operator UID allowlist, and chained PENDING/COMMITTED history with materialized head | Review exact wire/frame format, link calculation, genesis and epoch-transition authorization; verify access denial before claiming custody |
| Journal/head crash windows | ADR-0005 now specifies prepare before commit, confirm before acknowledgment, exact replay and a unified recovery table | Walk each crash point against the table; owner selected operator-only reconciliation for a missing pledged event, with no automatic cancellation |
| State and evidence registries | Task/control versions, transition eligibility and producer trust remain underspecified | Freeze transition/evidence tables, observer and evaluator identities, criteria coverage and all capability/attempt bindings |
| Runtime effect composition | ADR-0007 explicitly excludes runtime coordination, policy, capabilities, evaluation, state and recovery from Phase 1 E1 permission | Review an explicit runtime call/effect graph and authorize any necessary scoped rule qualification before effectful code |
| Phase 1 structural findings | E1 implementation and ADR-0007 acceptance exist; formal finding closure remains separate | Close each finding with evidence or name its release-debt owner and blocking disposition, as the phase plan requires |
| Implementation entry | ADR-0005 remains Proposed; affected contracts and traceability still describe planned controls | Accept the resolved design, align affected documents, and record bounded Phase 2 implementation authorization |

The owner selected Option 1: same VM, separate checkpoint custodian. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#owner-selected-storage-and-custody-direction) records the direction and its trust limits. The selection does not accept the complete ADR. A file beside the journal under the same writable identity does not establish independent custody; the interface and crash behavior still require review.

The revised [custodian protocol and recovery table](../decisions/0005-event-integrity-acceptance-and-recovery.md#custodian-operations-and-identities) replaces the earlier commit-then-advance proposal. A valid unattested chain is never sufficient for automatic attestation. Only the exact pre-pledged event can proceed to automatic confirmation after restart. This is a specification awaiting the owner's crash-point review, not new implementation evidence.

## Proposed review sequence

1. Review storage, checkpoint custody and crash-state behavior together. These determine which integrity and durability claims can be made and which fault proofs are meaningful.
2. Complete ADR-0005's wire, payload, transition, version and producer tables against those assumptions. Preserve the separate Phase 1 fixture format.
3. Review the runtime procedure graph. Classify every procedure High/Mid/Low and mark direct and transitive effects. Keep Mid transitively pure. Do not inherit the Phase 1 E1 allowance or hide effects behind callbacks or lifecycle code.
4. Align the contracts and verification plan, resolve the entry findings, and obtain acceptance and implementation authorization.
5. Only then implement the smallest no-op slice, followed by acceptance, durable recovery and replay under the accepted decisions. Do not claim phase exit from an encoder or happy-path demonstration alone.

This sequence is proposed work ordering, not authorization to bypass any phase-plan entry gate. No provider, real execution tool, production architecture, deployment or generalized orchestration belongs to this work.

## Required document alignment

Once the owner selects the design, update the existing authoritative documents rather than creating parallel contracts:

- ADR-0005 for the exact decisions and threat assumptions.
- `docs/contracts/event-integrity.md` for checkpoint-dependent detection scope and failure behavior. Its current broad removal-detection claim needs concrete custody assumptions before implementation can establish it.
- `docs/contracts/authoritative-state.md`, `model-proposals.md` and `independent-evaluation.md` for transaction, binding and producer rules.
- `docs/security/threat-model.md` and `trust-model.md` for journal/checkpoint attacker access and observer/evaluator trust. The threat model currently names chained hashes without specifying an independent head.
- `docs/architecture/dependency-rules.md`, `execution-pipeline.md`, `state-model.md` and `event-and-fact-model.md` for ownership, control versions and the reviewed call graph.
- `docs/engineering/coding-standard.md` for any separately approved runtime effect qualification; keep ADR-0007 unchanged.
- `docs/verification/negative-path-catalog.md` and `traceability-matrix.md` for concrete proof paths. Runtime rows remain planned until actual evidence exists.

## Verification discipline

No application code, dependency, workflow or test is introduced by this entry review. Run the existing documentation validator and diff checks for these edits. A foundation build cannot prove an unimplemented runtime design.

Before adding any test, present its concrete failure, supporting requirement or code path, existing coverage gap, expected confidence improvement and cost for owner review under the [coding standard](coding-standard.md#test-necessity). ADR-0005's verification matrix is a proof obligation, not permission for speculative test expansion.

After design authorization, evidence must bind the accepted store and checkpoint custodian to the tested source, target and toolchain. Preserve separate behavioral and structural reviews. Cross-platform encoding, rejection, concurrency, durable-boundary fault and replay evidence are required by the phase plan; none is supplied by the existing foundation controls.

## Entry disposition

| Gate | Result |
|---|---|
| Inspect merged phase plan and ADR-0005 | PASS at the reviewed baseline above |
| Assign ADR-0005 owner | PASS: Proto, explicit owner direction on 2026-10-18 |
| Select storage and custody direction | PASS: owner selected SQLite and separate same-VM custodian; implementation details remain unverified |
| Resolve and accept ADR-0005 | BLOCKED: decisions listed above |
| Close or explicitly assign structural release debt | BLOCKED: owner disposition not recorded |
| Align contracts and runtime effect boundaries | BLOCKED: depends on selected design |
| Begin runtime implementation | BLOCKED: design acceptance and bounded authorization still required |

Foundation obligations whose blocking gate is Phase 5 remain tracked in the phase plan. They are not silently promoted to Phase 2 blockers or treated as complete here.

## Staged governance tooling

The tooling candidate recognizes Phase 2 without declaring entry: project and Odin test manifest remain at Phase 1. The previous runner required phase 1 in [read_manifest, baseline lines 33–37](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/run_odin_tests.py#L33-L37); governance allowed only 0/1 in [baseline lines 28–31](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/governance.py#L28-L31).

The revised pure Mid `phase_two_record_findings` requires the ADR, phase plan, entry review, coding standard, dependency rules and trust/threat records, in addition to existing contracts. ADR-0005 must have only the recognized Accepted status line; a Proposed document with an appended Accepted marker does not pass. This bounded check cannot replace operator review or prove every entry gate. Missing/symlinked documents and malformed/unknown project phases remain rejected. Test manifest phase must be a known test phase matching the exact integer project phase; duplicate JSON keys remain rejected. Package/name/count/report discovery is unchanged.

`read_manifest` remains Low technical JSON representation acquisition/consistency checking, using Low `read_phase`/`unique_object`; it grants no runtime authority or ADR acceptance. The [existing procedure review](phase1-effect-composition-review.md) includes the new pure governance rule and prefix extraction helper. No Phase 1 E1 effect permission or runtime code is added.

Test necessity: the changed phase decision would otherwise admit a Phase 2 declaration without its governing records, or reject every valid future Phase 2 manifest. Existing foundation controls cover neither case. Two governance controls exercise accepted/proposed/conflicting status and required-file removal; one inventory control exercises matching Phase 2, mismatched/unknown/boolean phases and duplicate keys. Cost is three small controls, standard library only. Fixture-only Accepted text does not modify or accept the real ADR. The original 22 controls remain, with unknown-phase rejection moved from the newly recognized 2 to 3; observed total is 25. New runtime verification remains a separate plan and authorization.

Tooling candidate verification: documentation governance and all 25 Python controls pass. The revised runner also executed the unchanged two Odin packages/five named tests successfully with the pinned native macOS ARM64 compiler; fresh JSON reports are under `out/adr0005-tooling-tests/`. This verifies the runner regression, not Phase 2 runtime behavior.
