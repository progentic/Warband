# Phase 2 entry review

- **Status:** Design preparation; implementation blocked on the decisions below
- **Owner:** Proto, assigned to ADR-0005 on 2026-10-18
- **Historical roadmap review baseline:** `ccba4b68a959bacbfed1cdff40dcb109b8acaa9d`, merged PR #8
- **Implementation-preparation main baseline:** `3cbfd55b9157058cbd72dfcc6e14a59080925681`, later merged PR #9; descendant of the PR #8 baseline
- **Design publication scope:** PRs #10–#14; these changes are later than either historical baseline and do not accept ADR-0005 or activate Phase 2
- **Implementation phase:** `project.json` remains Phase 1

## Roles and source references

Proto is the project owner, ADR-0005 decision owner and acceptance operator for this design record. Here, an architectural “owner decision” or “operator acceptance” means Proto's explicit recorded decision. A future operational operator is a separately allowlisted OS identity for enrollment/reconciliation; that identity does not automatically receive ADR decision authority. No Unix UID or GitHub login is inferred from the name Proto.

Unless explicitly labeled PR #8, immutable baseline links below use the later PR #9 main commit, `3cbfd55`. Its source line references therefore refer to that later tree, not to `ccba4b6`. Candidate behavior is identified by its PR or amendment and is not attributed to either merged baseline.

## Boundary to prove

The next deliverable is a deterministic no-op authority path. A proposal receives a policy decision and bounded capability, produces independently evaluated evidence, and results in at most one accepted transition. Recovery and replay use recorded history. This is the Phase 2 outcome in the [phase plan](../governance/PHASE_PLAN.md#phase-2-deterministic-authority-core), not an implementation claim.

The governance review is **conditionally aligned**: preparation can proceed, but the current Proposed [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md) has the amended design in PR #10, with Option A specified but pending Proto's Gate 1 decision and ADR acceptance pending Gate 2. Its verification matrix already identifies the affected WB-CON-001 through WB-CON-009, WB-INV and WB-NEG requirements; this review does not duplicate or change those identifiers.

## Decisions required before implementation

| Decision | Current evidence or gap | Required owner disposition |
|---|---|---|
| Canonical event and payload specification | PR #9 left these fields open; PR #10 now supplies candidate binary v1 tables, limits, domains and vectors | Review exact wire tables, proposal fingerprint input, producer registry and independent golden vectors |
| Store and durability | Selected SQLite direction now proposes WAL/FULL, a writer gate across prepare/commit/confirm and checkpoint-confirmed read visibility; PR #10 proposes a verified SQLite source pin; target storage/flush evidence remains future work | Review constraints, locking and target flush assumptions; macOS development establishes no durability claim |
| Protected-head custody | Separate same-VM identity; draft local peer-credential protocol, distinct operator UID allowlist, and chained PENDING/COMMITTED history with materialized head | Review exact wire/frame format, link calculation, genesis and epoch-transition authorization; verify access denial before claiming custody |
| Journal/head crash windows | ADR-0005 now specifies prepare before commit, confirm before acknowledgment, exact replay and a unified recovery table | Walk each crash point against the table; owner selected operator-only reconciliation for a missing pledged event, with no automatic cancellation |
| State and evidence registries | PR #10 supplies separate versions, transition rules and producer identities; acceptance and implementation evidence remain pending | Freeze transition/evidence tables, observer and evaluator identities, criteria coverage and all capability/attempt bindings |
| Runtime effect composition | ADR-0007 explicitly excludes runtime coordination, policy, capabilities, evaluation, state and recovery from Phase 1 E1 permission | Review an explicit runtime call/effect graph and authorize any necessary scoped rule qualification before effectful code |
| Phase 1 structural findings | E1 implementation and ADR-0007 acceptance exist; formal finding closure remains separate | Close each finding with evidence or name its release-debt owner and blocking disposition, as the phase plan requires |
| Implementation entry | ADR-0005 remains Proposed; affected contracts and traceability still describe planned controls | Accept the resolved design, align affected documents, and record bounded Phase 2 implementation authorization |

The owner selected Option 1: same VM, separate checkpoint custodian. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#owner-selected-storage-and-custody-direction) records the direction and its trust limits. The selection does not accept the complete ADR. A file beside the journal under the same writable identity does not establish independent custody; the amended interface and crash behavior are now concrete candidates awaiting operator review.

The revised [custodian protocol and recovery table](../decisions/0005-event-integrity-acceptance-and-recovery.md#custodian-operations-and-identities) replaces the earlier commit-then-advance proposal. A valid unattested chain is never sufficient for automatic attestation. Only the exact pre-pledged event can proceed to automatic confirmation after restart. This is a specification awaiting the owner's crash-point review, not new implementation evidence.

## Proposed review sequence

1. Review the full identity tuple and reference/uniqueness rules.
2. Review the exact binary integer/field encoding, payload schemas, hash domains and custody frame tables. Preserve the separate Phase 1 fixture format.
3. Apply those byte rules to custody behavior, enrollment/epoch changes and the crash-state walkthrough; resolve the denied-request audit options below. This step validates an existing wire candidate rather than defining it circularly.
4. Review task/control versions, transition/evidence rules and observer/evaluator trust.
5. Review the enumerated runtime High/Mid/Low graph and exact SQLite pin; keep Mid transitively pure and do not inherit Phase 1 E1 permission.
6. Review the aligned contracts, verification plan and named debt disposition, including severity and independence conditions.
7. Record explicit architectural acceptance with its source and decision-commit reference, then separately authorize Phase 2 entry/implementation. Implement the no-op slices only after those gates; a codec or happy-path demonstration cannot close the phase.

This sequence is proposed work ordering, not authorization to bypass any phase-plan entry gate. No provider, real execution tool, production architecture, deployment or generalized orchestration belongs to this work.

## Required document alignment

PR #12 proposes these updates in the existing documents rather than creating parallel contracts. This list explains the baseline gaps and review responsibilities; it does not describe those drafts as implemented runtime controls:

- ADR-0005 for the exact decisions and threat assumptions.
- `docs/contracts/event-integrity.md` for checkpoint-dependent detection scope and failure behavior. The unqualified claim in [PR #9 baseline line 17](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/contracts/event-integrity.md#L17) is qualified by the same-VM threat assumptions in PR #12.
- `docs/contracts/authoritative-state.md`, `model-proposals.md` and `independent-evaluation.md` for transaction, binding and producer rules.
- `docs/security/threat-model.md` and `trust-model.md` for journal/checkpoint attacker access and observer/evaluator trust. The [PR #9 threat baseline lines 29–31](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/security/threat-model.md#L29-L31) names chained hashes; PR #12 adds independent custody and its limits.
- `docs/architecture/dependency-rules.md`, `execution-pipeline.md`, `state-model.md` and `event-and-fact-model.md` for ownership, control versions and the reviewed call graph.
- `docs/engineering/coding-standard.md` for any separately approved runtime effect qualification; keep ADR-0007 unchanged.
- `docs/verification/negative-path-catalog.md` and `traceability-matrix.md` for concrete proof paths. Runtime rows remain planned until actual evidence exists.

## Verification discipline

The documentation-only ADR amendment and static vectors in [PR #10](https://github.com/progentic/Warband/pull/10) introduce no application code, installed dependency, workflow or test. This is not a claim about the full PR stack: [PR #11](https://github.com/progentic/Warband/pull/11) changes governance/test-tooling code and adds three controls, as described below. This entry-review text is documentation; its claims distinguish those scopes. Run documentation governance, the governance controls and diff checks for the candidate. A foundation build cannot prove an unimplemented runtime design.

Before adding any test, present its concrete failure, supporting requirement or code path, existing coverage gap, expected confidence improvement and cost for owner review under the [coding standard](coding-standard.md#test-necessity). ADR-0005's verification matrix is a proof obligation, not permission for speculative test expansion.

After design authorization, evidence must bind the accepted store and checkpoint custodian to the tested source, target and toolchain. Preserve separate behavioral and structural reviews. Cross-platform encoding, rejection, concurrency, durable-boundary fault and replay evidence are required by the phase plan; none is supplied by the existing foundation controls.

## Entry disposition

| Gate | Result |
|---|---|
| Inspect merged phase plan and ADR-0005 | PASS at the reviewed baseline above |
| Assign ADR-0005 owner | PASS: Proto, explicit owner direction on 2026-10-18 |
| Select storage and custody direction | PASS: owner selected SQLite and separate same-VM custodian; implementation details remain unverified |
| Resolve and accept ADR-0005 | BLOCKED on the denied-custodian-request audit decision and explicit operator acceptance; amended formats, pin and graph are drafted |
| Close or explicitly assign structural release debt | REVIEW PENDING: three named Proto-owned debts with a binding Phase 5 entry deadline and unfulfilled severity/independent-closure review in the verification plan; no automatic closure |
| Align contracts and runtime effect boundaries | REVIEW PENDING: aligned contract candidate and enumerated Phase 2 graph; no runtime permission active |
| Begin runtime implementation | BLOCKED: design acceptance and bounded authorization still required |

Foundation obligations whose blocking gate is Phase 5 remain tracked in the phase plan. They are not silently promoted to Phase 2 blockers or treated as complete here.

## Staged governance tooling

The tooling candidate recognizes Phase 2 without declaring entry: project and Odin test manifest remain at Phase 1. The previous runner required phase 1 in [read_manifest, baseline lines 33–37](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/run_odin_tests.py#L33-L37); governance allowed only 0/1 in [baseline lines 28–31](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/governance.py#L28-L31).

The revised pure Mid `phase_two_record_findings` requires the ADR, phase plan, entry review, coding standard, dependency rules and trust/threat records, in addition to existing contracts. ADR-0005 must have only the recognized Accepted status line plus the named acceptance authority, decision-commit reference and accepted-source SHA described below; a Proposed document with an appended Accepted marker does not pass. These are bounded content/format checks, not proof of operator identity, commit existence, ancestry or a separate decision. They cannot replace operator review or prove every entry gate. Missing/symlinked documents and malformed/unknown project phases remain rejected. Test manifest phase must be a known test phase matching the exact integer project phase; duplicate JSON keys remain rejected. Package/name/count/report discovery is unchanged.

`read_manifest` remains Low technical JSON representation acquisition/consistency checking, using Low `read_phase`/`unique_object`; it grants no runtime authority or ADR acceptance. The [existing procedure review](phase1-effect-composition-review.md) includes the new pure governance rule and prefix extraction helper. No Phase 1 E1 effect permission or runtime code is added.

Test necessity: the changed phase decision would otherwise admit a Phase 2 declaration without its governing records, or reject every valid future Phase 2 manifest. Existing foundation controls cover neither case. The current owner clarification reviews this justification at the PR #11 review stage, after the three controls were already authored; no prior-to-addition review is recorded. This retrospective review does not demonstrate compliance with the prior-review timing rule. Future new tests require review before addition. Two governance controls exercise accepted/proposed/conflicting status and required-file removal; one inventory control exercises matching Phase 2, mismatched/unknown/boolean phases and duplicate keys. Cost is three small controls, standard library only. Fixture-only Accepted text does not modify or accept the real ADR. The original 22 controls remain, with unknown-phase rejection moved from the newly recognized 2 to 3; observed total is 25. New runtime verification remains a separate plan and authorization.

Tooling candidate verification: documentation governance and all 25 Python controls pass. The revised runner also executed the unchanged two Odin packages/five named tests successfully with the pinned native macOS ARM64 compiler; fresh JSON reports are under `out/adr0005-tooling-tests/`. This verifies the runner regression, not Phase 2 runtime behavior.

## Verification and finding-disposition candidate

The [verification plan](../verification/phase2-verification-plan.md) defines required proof groups, crash checkpoints and implementation slices. Its source-based Phase 1 findings review records the permitted named-release-debt alternative; formal owner closure remains separate. All runtime verification remains unexecuted.

The [phase gate table](../governance/PHASE_PLAN.md#phase-26-review-and-exit-gate-table) stages the no-op implementation and later release boundaries. ADR-0005 acceptance, Phase 2 entry and future phase/release authorizations remain separate operator decisions.

## Decision handoff

| Item | Candidate decision | Alternative considered |
|---|---|---|
| Identity | Full store/epoch/sequence for references and uniqueness | Store/sequence with globally non-reusable sequences |
| Bytes | Fixed versioned binary event/custody formats, explicit limits/domains, static independent vectors | Canonical JSON or generic map payloads |
| Enrollment/epochs | Empty-store out-of-band operator enrollment; bound epoch change, old evidence retained, missing pledge operator-only | Owner-signed epoch requests: portable/verifiable authorization, but add protected key custody, rotation and replay handling; not selected. Automatic enrollment/reset from SQLite: rejected because the rewriteable store would establish its own trust |
| Versions/acceptance | Separate task/control/attempt identities and atomic checked acceptance | One shared counter, rejected |
| Evidence trust | Registered separate observation/evaluation/state responsibilities, same-process limitation | One success flag or extra services |
| Effects | Separate enumerated Phase 2 High graph; universal pure Mid | Effectful Mid or blanket High-to-Low permission, rejected |
| SQLite | Proposed 3.54.1 source pin with [recorded verification](#sqlite-verification-evidence), future project-local static profile and WAL/FULL | Per-OS distribution libraries |
| Custodian rejection audit | Pending; candidate is a bounded durable rejection receipt without changing checkpoint/pledge | Runtime-only audit handoff, or defer acceptance; options and consequences below |

The operator question on custody rejection audit metadata remains open in the ADR's acceptance-issue section. This is an actual WB-CON-007 coverage question, not a request for another blanket implementation approval. Resolve it before claiming the candidate is acceptance-ready. After that, operator acceptance, protected integration and explicit Phase 2 entry remain distinct decisions. Future operations/security/release owner assignments and production-target selection are deferred to their named phase gates, not guessed here.

Design publication order is PR #10 decisions, #11 tooling, #12 contracts, #13 verification/findings, #14 roadmap. Each is retargeted to main after its predecessor lands and merges only with passing checks on its current head. This publication does not select Option A, accept ADR-0005 or authorize Phase 2 entry. Local documentation governance and governance controls ran before every commit, including stack-update merges. Final hosted check results must be bound to each actual head SHA in the handoff rather than inherited from an earlier passing run.

## Acceptance provenance gate

A future Accepted ADR-0005 must name all three fields, with one unambiguous recognized value for each:

```text
- **Acceptance authority:** Proto (project owner)
- **Acceptance record:** https://github.com/progentic/Warband/commit/<40 lowercase hex characters>
- **Accepted source:** <40 lowercase hex characters>
```

The record must be an explicit named operator decision, not a passing run, this draft PR or a commit that only changes a status label. It must identify the reviewed source, decision and authority. Before opening the Phase 2 activation PR, the operator must verify the referenced decision commit is already in protected main, applies to that exact accepted source, and authorizes acceptance separately from implementation entry. The phase activation PR cites that record; it must not manufacture acceptance and phase entry together.

The pure gate rejects missing/malformed references or an absent authority line. It does not query GitHub, prove who made a decision or verify the referenced commit's content/ancestry. A same-PR fabricated reference could still satisfy syntax; human review against protected history remains mandatory. No real acceptance reference is filled in while the ADR is Proposed. Fixture-only synthetic references exercise parsing, not approval.

Test necessity for this correction is concrete: a status-only phase change passed the previous gate, while the stated process required provenance. The existing accepted-decision control now rejects status-only, missing-field and malformed-reference cases; no new test or quota is added (25 total). The owner identified this concrete status-only failure in finding 6 before this correction; the existing control is extended to that requested behavior, rather than adding speculative tests. The bounded structural control permits only the added pure regex primitive/import and still rejects an injected `os` import, effects and upward dependencies. No phase declaration, runtime code or workflow changes.

## Debt gate and independent review

The binding closure deadline for the three named debts is **Phase 5 entry**. “v1 blocked” is a downstream consequence, not an alternative later deadline. Proto owns remediation and the ADR; ownership is not independent review. No finding is closed and no independence rule is represented as fulfilled. Severity and an independent reviewer are unassigned. Before closure, the assigned security triage owner records severity/impact; a critical/high finding requires confirmation by a named independent reviewer under [the merged review rule, lines 265–274](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/governance/PHASE_PLAN.md#L265-L274). The finding/fix author cannot be its sole closer. Medium/low disposition follows the project-owner acceptance or corrective schedule rule. The [per-finding disposition](../verification/phase2-verification-plan.md#ownership-severity-and-independent-review) retains those conditions. No self-approval exemption is implied.

## Denied custodian requests: operator decision required

WB-CON-007 requires security-relevant decisions to produce audit events ([constitution lines 31–33](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/foundation/runtime-constitution.md#L31-L33)). The ADR now specifies Option A's REJECTION frame, bounded digest, kernel-observed peer fields, durable-denial ordering and audit-only import; Proto's Gate 1 selection remains pending. Authentication failure must still reject; audit handling cannot grant the request or replace a checkpoint. No option is selected by this clarification.

| Option | Benefit | Consequence / constraint | Candidate disposition |
|---|---|---|---|
| A. Bounded durable custody rejection receipt | Custodian retains independent evidence of its own denial; does not rely solely on the runtime identity being denied | The pending ADR specification defines frame kind 5, an 88-byte payload, bounded request digest and kernel-observed peer identity, persistence/acknowledgment order and storage-failure behavior. No raw request/secrets, head movement or pending-pledge change. Review how receipts are represented in the single audit history/projection under ADR-0003; metadata alone must not be claimed as completed end-to-end audit coverage | Specified as pending Option A; Gate 1 selection remains with Proto |
| B. Runtime-only RejectionRecorded handoff | Reuses the event history without a new custody frame | A down or compromised runtime could omit the custodian denial; without an independently retained receipt this does not close the identified threat-model gap | Not recommended as the sole evidence |
| C. Defer acceptance | Preserves current authority/custody choices without pretending coverage exists | No audit-gap resolution or acceptance-ready claim; implementation entry remains blocked until a reviewed design closes WB-CON-007 | Safe pending disposition |

The publication task specifies A as pending, including the single-event-history handoff; Gate 1 remains Proto's decision. If audit persistence fails, do not report a durable audit receipt or permit the denied operation; preserve the fault and fail closed. This does not authorize another physical authoritative event ledger, batching, remote custody or a runtime implementation. The existing same-VM, prepare/confirm, per-event and manual-reconciliation decisions remain fixed.

## SQLite verification evidence

The proposed pin is recorded in [PR #10](https://github.com/progentic/Warband/pull/10), with immutable [ADR verification details at 154d879, lines 346–365](https://github.com/progentic/Warband/blob/154d879735a2e4b7b3532ed4807c6ff87cb8e7bb/docs/decisions/0005-event-integrity-acceptance-and-recovery.md#L346-L365). Upstream [3.54.1 release notes](https://www.sqlite.org/releaselog/3_54_1.html) identify the release/source ID and sqlite3.c SHA3-256; the [official download page](https://www.sqlite.org/download.html) publishes the amalgamation archive SHA3-256. The exact archive is [sqlite-amalgamation-3540100.zip](https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip).

Downloaded archive bytes and extracted sqlite3.c were hashed and matched those published digests. Archive SHA-256 was independently computed and is labeled as such in the ADR; it is not falsely attributed to the upstream SHA3 listing. Verification receipts are recorded in the ADR table, so reviewers need no local path. This is source identity/digest verification and release-note review, not a SQLite source audit, installed library, working Odin binding, runtime compatibility result or durability proof. If the upstream sources cannot be independently retrieved, retain that review limitation rather than replacing the pin by assumption.
