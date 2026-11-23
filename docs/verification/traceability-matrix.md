# Traceability Matrix

This matrix links constitutional rules to contracts, planned implementation, verification, and user-visible behavior.

## Resource-limit review

[WB-EXC-001 status and provisional limits](../decisions/0008-phase2-resource-limits.md) and the [fault/measurement plan](phase2-verification-plan.md#proposed-limits-and-measurement) provide the review records for WB-CON-007/008/009 and WB-INV-004/006/008/009, with applicable WB-NEG-005/006/009 cases. Evidence-backed statuses remain in the rows below.

The [runtime debit boundary proof](phase2-crash-coverage.md#runtime-session-debit-boundary) checks WB-CON-007/008/009 recovery behavior. The harness in `tests/measurement/runtime_debit_boundary.py` verifies the confirmed checkpoint, pending pledge and SQLite receipt binding when the runtime refuses further work.

The [custodian cold-start cases](phase2-crash-coverage.md#custodian-cold-start-boundaries) exercise WB-CON-007/008/009 with the ordinary Linux service and startup witnesses. `tests/measurement/cold_start_boundaries.py` compares custody bytes, the published head and authenticated readiness across byte, arena and deadline boundaries.

The [SQLite WAL sync proof](phase2-crash-coverage.md#sqlite-wal-commit-sync-failure) supplies scoped WB-CON-007/008/009 recovery evidence. On x64-review a failed COMMIT sync withheld acknowledgment. The retained receipt event and pledge supported one exact confirmation on restart.

## Phase 2 no-op authority core

These statuses apply to the preproduction no-op path in the [tested inventory](phase2-crash-coverage.md#slice-6-evidence-inventory). The [verification plan](phase2-verification-plan.md#required-proof-groups) maps the cases to their contracts. Source inspection, pure tests, Linux process evidence and operator decisions carry the distinct scopes below.

| Requirement | Invariants and negative cases | Evidence and boundary |
|---|---|---|
| WB-CON-001 | WB-INV-001/009; WB-NEG-005/006 | Only the acceptor advances task state. Competing processes produced one accepted transition; an exact retry returned the recorded result. |
| WB-CON-002 | WB-INV-001/002; WB-NEG-001 | The canonical no-op proposal codec rejects malformed payloads and the live gate requires a validated, checkpoint-covered proposal. Provider input is deferred. |
| WB-CON-003 | WB-INV-005; WB-NEG-007 | The observer compares the primitive’s returned bytes. The independent evaluator reads persisted evidence and recomputes its digest; a lost return led to an indeterminate observation and rejected verdict. |
| WB-CON-004 | WB-INV-002/007; WB-NEG-008/010 | The no-op path checks policy version, recovery choice and proposal fingerprint. Approval-required proposals are ineligible. Positive CLI approval and mutation after real approval belong to Phase 3. |
| WB-CON-005 | WB-INV-003; WB-NEG-003/004 | Supplied-clock tests reject expiry at equality. The issuing process dispatched once; the fresh process refused the same durable claim. Separate Linux UID tests enforce custody/operator boundaries. |
| WB-CON-006 | WB-INV-005/009; WB-NEG-006/007 | A verified evaluation bound to the consumed claim permits a single task/control advance. Revoked, rejected and stale evidence withheld acceptance. |
| WB-CON-007 | WB-INV-006; WB-NEG-009/012 | Canonical codecs, authenticated custody and the importer bound each tested denial event to its receipt. Complete corruption withheld replay; validated torn final suffixes were trimmed. Sustained-load retention beyond the measured envelope is unqualified. |
| WB-CON-008 | WB-INV-008/009; WB-NEG-005/006/009 | Replay matched the mixed-history oracle and the live single-task projections. Wrong-role references and altered history withheld the projection. Missed acknowledgments and competing acceptors preserved the original result. |
| WB-CON-009 | WB-INV-004; WB-NEG-010 | The codec requires the registered recovery choice. Crash and storage-error cases selected recovery from the retained bytes; Proto rehearsed continued halt on missing and unattested events. |
| WB-CON-010 | WB-INV-010 | The provider and learned-promotion paths remain outside this phase. |

WB-NEG-002/011 require tool registration and output handling in later phases. WB-NEG-013–018 retain their foundation controls. Linux fault results belong to the tested store, custodian and kernels. The [exit record](../governance/phase2-exit.md) carries the unqualified envelopes and later gates.

Functional replay supplies scoped evidence for WB-CON-001/006/007/008, WB-INV-006/008/009 and WB-NEG-005/006/009/012. Confirmed no-op histories reproduce the independent projections, and all five tamper cases withhold the projection. The [crash matrix](phase2-crash-coverage.md) identifies the recovery evidence for each boundary. [Replay qualification](../decisions/0005-event-integrity-acceptance-and-recovery.md#slice-6-functional-replay-qualification).

[Isolated custodian evidence](isolated-linux-custodian.md) exercises the custody portion of WB-CON-007/008/009 through kernel identity checks, receipt persistence, exact replay and startup reconciliation. Later receipt and WAL cases qualify exactly-once import on the isolated store; cross-store recovery remains outside that claim.

WB-CON-005/008 and WB-INV-003 require a [fresh-runtime dispatch denial](phase2-verification-plan.md#fresh-runtime-dispatch-denial). The paired Linux proof verified this boundary on x64-review. The issuer dispatched once and the fresh process withheld dispatch with a confirmed rejection while the original interval was still open.

For WB-CON-003/006/008 and WB-INV-005, the [isolated no-op observation and evaluation proof](phase2-verification-plan.md#no-op-observed-return-and-verdict) covers confirmed evidence and idempotent evaluation. For this path, WB-CON-001/006/008 and WB-INV-001/005/008 also have [state acceptance and competing-acceptor evidence](phase2-verification-plan.md#isolated-state-acceptance-and-contention).

## Phase 3 marker binding

WB-INV-007 and WB-NEG-008 have pure codec evidence for kinds 11/12. A changed binding withholds a match against the original approval. The real CLI approval and denial-before-dispatch tests are still owed. [Golden and compatibility results](../decisions/0009-controlled-local-marker-execution.md#proposal-and-approval-codec-qualification)

### Marker evidence codec qualification

The portable audit codecs encode and decode the five fixed formats in [ADR-0009](../decisions/0009-controlled-local-marker-execution.md#marker-event-wire-profile-1). The independent literals in `tests/odin/audit/marker_evidence_vectors.odin` extend the published kind-12 head through permit, claim, observation, evaluation and acceptance. The 169/200/180/203/193-byte records reproduce each event digest and linked head. The final head is `2a9ae56e6a96ea3f7ca3a6c72b8bf83639ed42273752715f6dda201976d7c3c1`.

The tests distinguish an absent marker (zero length and hash) from a fully read empty regular file (zero length and SHA-256 of the empty string). They check all proof-flag combinations, all delivery and verdict codes, fixed fields, Ref scope/order and checked version increments. The [marker replay qualification](#marker-chain-replay) covers historical reference resolution and uniqueness. The live worker, CLI approval and denial before dispatch remain separate obligations. The manifest verified 68 named tests in seven packages on macOS ARM64 and Linux x64.

### Marker-chain replay

For WB-CON-001/003/006/008 and WB-INV-001/005/008/009, `src/replay:project_markers` checks a supplied authenticated enrollment checkpoint, any retained epoch handoffs, and the live committed head before reducing the confirmed rows. The ordinary v1 reader remains the CLI entry point. On the two 64-bit targets the v1 record and projected task still occupy 232 and 104 bytes. The marker reader retains the proposal binding, fingerprint, payload length and digest; evaluation resolves the confirmed approval and observation and checks the recorded verdict against both.

The fixture takes the first two custody frames and sequence-zero head from the sealed PR #94 x64-review fault capture. From that root it constructs a valid v1 TaskCreated and the seven marker events, with test PENDING/COMMITTED custody frames. Independent packing gives final head `2a7b228ff770fab2e26583c127366359963e419bbfc761194b20118132bf6c59`. Prefix oracles check task/control 1/0 through approval, 1/1 at permit, 1/2 from consumption through evaluation, and 2/3 only at confirmed acceptance. A present but pending acceptance leaves the claim consumed and the task incomplete. Replaying each confirmed prefix twice produced the same projection.

The semantic cases reseal every changed body and validate the corresponding custody history before checking the reducer’s error and empty output. Cases include crossed v1/v2 roles in both directions, rejected approval, stale versions, duplicate records, changed fingerprints or observation digests, revocation and terminal disposition. A lost reply with exact approved contents verified. Absence remained incomplete, including for an approved empty payload. Conflicting contents and missing inspection proofs required operator reconciliation. These are constructed history cases. WB-INV-007 and WB-NEG-008 still owe real CLI and execution-path evidence.

On macOS ARM64 and x64-review the manifest verified 71 named tests in seven packages, including six replay tests. In the legacy task-capacity regression, the three paired runs reproduced 328 actual / 470 charged without a denial and 470 / 663 with one. The runtime-session equality and single-debit refusal cases also passed.

## Historical Phase 1 implementation evidence

At Phase 1 closure the constitutional rows were planned. Foundation tests do not establish runtime authority, model isolation, evidence acceptance, or replay.

| Foundation requirement | Implementation | Verification | Status |
|---|---|---|---|
| WB-P1-001: pinned compiler | `toolchain/odin.lock.json`, `scripts/build_odin.sh`, `scripts/assert_toolchain.py` | Source HEAD, build-script digest, PATH/version/resources, LLVM version | verified locally on macOS ARM64 and Linux x64 |
| WB-P1-002: executable identity | `cmd/warband/`, `scripts/build_warband.sh`, `scripts/build_manifest.py` | Executable metadata and CLI smoke | ARM64 Mach-O and x64 ELF verified locally |
| WB-P1-003: explicit phase | `project.json`, `scripts/check_docs.py`, `scripts/governance.py`, `scripts/document_io.py` | Governance fixtures; WB-NEG-013/016 | locally verified |
| WB-P1-004: complete test execution | `tests/odin-packages.json`, `scripts/run_odin_tests.py`, `scripts/test_inventory.py` | Exact source/manifest/report inventory; WB-NEG-014 | 2 packages / 5 tests verified separately on macOS and Linux; 17 Python controls |
| WB-P1-005: VM preparation | `vm/lima.yaml`, `vm/selection.json` | Explicit development architecture; no mounts/forwarded application ports; image gate | original ARM profile pending; reviewed x64 verification VM provisioned |
| WB-P1-006: hosted CI | `.github/workflows/docs.yml`, `.github/workflows/phase1.yml` | actionlint, pinned actions, read-only token, credential-free checkout; `docs/verification/phase1-publication-evidence.md`; `docs/governance/phase1-protection-proposal.md` | Linux/macOS/docs passed at d6448e1; artifacts inspected; strict required checks applied; blocked negative probe and failure uploads verified |
| WB-P1-007: deterministic data | `src/domain/`, `src/fixture/` | Golden bytes, supplied IDs/tick, round trip, distinct types, WB-NEG-015 | verified locally on macOS and Linux |
| WB-P1-008: explicit entrypoint boundaries | `cmd/warband/main.odin`, `scripts/check_docs.py`, `scripts/build_manifest.py`, `scripts/manifest_rules.py`, `scripts/manifest_io.py` | `tests/governance/test_manifest_rules.py`, `tests/governance/test_e1_structure.py`, existing CLI smoke, manifest parity and WB-NEG-017/018; `docs/verification/phase1-entrypoint-evidence.md`; `docs/engineering/phase1-effect-composition-review.md` | E1 published at v0.0.0 / 8afe351; ADR-0007 Accepted; pure dependencies and behavior verified separately; finding closure pending |

## Invariant coverage status

Phase 2 entry is authorized by the separate record in [the entry review](../engineering/phase2-entry-review.md), following ADR-0005 acceptance against `84cfc937` and protected decision commit `f46ae949`. The first slice is limited to pure event-reference validation and sequence overflow rejection. It does not change the planned runtime coverage below or establish storage uniqueness, acceptance, custody, recovery or replay.

`src/domain/events/identity.odin` defines the full store/epoch/sequence value and rejects empty identity fields, wrong explicit store/epoch and sequence overflow. The separately authorized pure epoch follow-on adds `next_epoch`, rejecting zero and overflow without authorizing epoch administration. At that increment, `tests/odin/event_identity/event_identity_test.odin` contained three focused tests and the manifest declared three packages/eight tests, retaining the original five. This is partial domain evidence for WB-CON-008/WB-NEG-006, not a passing runtime uniqueness or replay gate. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#pure-epoch-advancement-follow-on-recorded-2026-11-10) records the decision, scope and test necessity.

The authorized `src/domain/events/prepare.odin` follow-on adds supplied-value prepare classification. One focused test in the same identity package covers eligibility, exact pending replay and four binding/order rejections; the manifest now declares three packages/nine tests. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#pure-prepare-classification-follow-on-recorded-2026-11-10) records its scope and necessity. This adds partial domain evidence for WB-CON-008/WB-NEG-005/006 only; authentication, link/history validation, persistence, actual receipts, confirm, recovery and runtime replay remain unimplemented.

`src/domain/events/confirm.odin` adds pure confirm classification under the [authorized entry](../engineering/phase2-entry-review.md#pure-confirm-classification-authorized-2026-11-11). One focused test covers pending binding, publication readiness and exact latest-committed replay preserving a newer pledge; the manifest declares three packages/ten tests. This is partial WB-CON-008/WB-INV-008 and WB-NEG-005/006 domain evidence. Actual confirmation, authentication, durability and receipts remain unimplemented.

`src/domain/events/recovery.odin` adds the [authorized pure recovery slice](../engineering/phase2-entry-review.md#pure-recovery-classification-authorized-2026-11-12), with one focused named-outcome/precedence test and three packages/eleven declared tests. This adds partial WB-CON-007/008/009, WB-INV-004/006/008/009 and WB-NEG-005/006/009 domain coverage. Persisted integrity, crash recovery and operator reconciliation remain future verification.

`src/custody/pledge.odin` adds the [authorized fixed pledge codec/link hash](../engineering/phase2-entry-review.md#pledge-codec-and-link-hash-authorized-2026-11-12). Independent field-table/OpenSSL reproduction preceded the two focused tests in `tests/odin/custody/pledge_test.odin`; the manifest now declares four packages/thirteen tests. This is partial canonical-byte, link-binding and malformed-input evidence for WB-CON-007/008, WB-INV-006/008/009 and WB-NEG-001/009/012. It establishes no authenticity, persisted integrity, custody, Linux durability or runtime replay.

The [TaskCreated codec record](../decisions/0005-event-integrity-acceptance-and-recovery.md#taskcreated-canonical-codec-recorded-2026-11-13) adds fixed canonical event bytes and body-digest evidence for WB-CON-007/008 and WB-NEG-001/012. Two focused tests cover the independent vector and implemented rejection paths; five packages/fifteen tests are declared. This is partial encoding evidence; runtime audit, authenticity, persisted integrity and replay rows remain planned.

The [custody frame/head slice](../decisions/0005-event-integrity-acceptance-and-recovery.md#custody-frame-and-head-codecs-recorded-2026-11-15) adds fixed frame/head bytes, checksum and supplied-context binding coverage for WB-CON-007/008, WB-INV-006/008/009 and WB-NEG-009/012. Three focused tests distinguish truncation from complete corruption and verify the published vectors; five packages/eighteen tests are declared. Actual history validation, repair, authenticated custody and durable publication remain unverified.

The [administrative/rejection payload slice](../decisions/0005-event-integrity-acceptance-and-recovery.md#genesis-epoch-and-rejection-payloads-recorded-2026-11-15) adds bounded payload bytes and hash-binding tests for WB-CON-007/008/009, WB-INV-004/006/008/009 and applicable WB-NEG-001/006/009/012 cases. Five packages/twenty-four tests are declared. Operator authentication, authorization-ID uniqueness, actual epoch installation, rejection persistence and kind-3–5 frame integration remain unimplemented.

The [all-kind framing increment](../decisions/0005-event-integrity-acceptance-and-recovery.md#all-kind-custody-framing-authorized-2026-11-16) adds format and caller-supplied ordinal/predecessor binding for kinds 3–5, with payload delegation, bounded lengths and shared corruption checks. Two tests extend partial WB-CON-007/008, WB-INV-006/008/009 and WB-NEG-009/012 evidence; five packages/twenty-six tests are declared. Authenticated history, administration and persistence remain future boundaries.

The [ProposalRecorded slice](../decisions/0005-event-integrity-acceptance-and-recovery.md#proposalrecorded-codec-authorized-2026-11-16) adds canonical kind-2 bytes, whole-payload fingerprinting and representation rejection evidence for WB-CON-007/008 and applicable WB-NEG-001/012 cases. The TaskCreated tests remain unchanged; two new tests bring the manifest to five packages/twenty-eight tests. State/version uniqueness, authorization and approval enforcement remain future boundaries.

The [AuthorizationRecorded codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#authorizationrecorded-codec-authorized-2026-11-16) adds kind-3 canonical bytes and conditional representation checks for partial WB-CON-004/005/007/008 and applicable WB-NEG-001/012 coverage. Two focused tests bring the manifest to five packages/thirty tests. Runtime policy, live expiry, reference closure, capability uniqueness and approval enforcement remain unverified.

The [DispatchClaimed codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#dispatchclaimed-codec-authorized-2026-11-16) adds canonical kind-4 bytes and representation/reference-order rejection coverage for partial WB-CON-007/008 and applicable WB-NEG-001/012 cases. Two focused tests bring the manifest to five packages/thirty-two tests. Authorization resolution, version/fingerprint binding, capability consumption, live expiry and actual dispatch remain future boundaries.

The [ObservationRecorded codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#observationrecorded-codec-authorized-2026-11-17) adds canonical kind-5 bytes and outcome/byte-pairing rejection coverage for partial WB-CON-007/008 and applicable WB-NEG-001/012 cases. Two tests bring the manifest to five packages/thirty-four tests. Observer authenticity, claim/attempt binding, observation uniqueness, independent evaluation and completion remain future boundaries.

The [evaluation and transition codecs](../decisions/0005-event-integrity-acceptance-and-recovery.md#evaluationrecorded-and-transitionaccepted-codecs-authorized-2026-11-17) add partial WB-CON-007/008 representation evidence. Four focused tests cover canonical bytes, references, verdict and checked task-version advancement. The manifest declares five packages and 38 tests. The later [no-op evaluation proof](phase2-verification-plan.md#no-op-observed-return-and-verdict) covers the isolated runtime verdict. The isolated state acceptance qualification adds transactional evidence for WB-CON-003/006. Phase exit traceability remains pending.

The [revocation and disposition codecs](../decisions/0005-event-integrity-acceptance-and-recovery.md#capabilityrevoked-and-attemptdisposition-authorized-2026-11-17) extend partial WB-CON-007/008 encoding and rejection evidence. Four tests cover the two fixed representations. Grant-state checks, claim termination and transactional updates require runtime verification. The manifest declares five packages and 42 tests.

The [RejectionRecorded codec](../decisions/0005-event-integrity-acceptance-and-recovery.md#rejectionrecorded-codec-authorized-2026-11-17) adds kind-8 byte, role and reference checks for partial WB-CON-007/008 and WB-NEG-001/012 coverage. Two named tests complete the codec inventory of five packages and 44 tests. Authenticated denial recording and receipt import remain future evidence.

The [single-epoch custody history validator](../decisions/0005-event-integrity-acceptance-and-recovery.md#single-epoch-custody-history-validation-authorized-2026-11-17) supplies partial WB-CON-007/008, WB-INV-006/009 and WB-NEG-009 evidence for record linkage, pledge pairing and published-head agreement. The manifest declares five packages and 45 tests. Physical tail repair, authentication and storage durability remain open.

The [WBCR and peer-role increment](../decisions/0005-event-integrity-acceptance-and-recovery.md#pure-custodian-requests-and-peer-roles-authorized-2026-11-17) covers canonical request bytes and supplied-value role separation for partial WB-CON-005/007 and WB-NEG-003/012 evidence. The manifest declares 48 tests. Connected-socket credential acquisition and Linux permission denials remain future evidence.

The [WBRS reply increment](../decisions/0005-event-integrity-acceptance-and-recovery.md#wbrs-replies-and-disclosure-authorized-2026-11-17) adds partial WB-CON-005/007 evidence for context-dependent disclosure and receipt representation. Three tests bring the inventory to five packages and 51 tests. Actual peer identity, durable acknowledgment and earliest-receipt selection require integration evidence.

The [multi-epoch validator](../decisions/0005-event-integrity-acceptance-and-recovery.md#multi-epoch-history-validation-authorized-2026-11-17) extends partial WB-CON-007/008 and WB-NEG-006/009 evidence to pre-enrollment denials, pending-hash binding and store-wide authorization-ID uniqueness. The inventory declares 52 tests. Linux custody access controls, persisted ordering, repair and reconciliation remain future evidence.

The [3b Gate 0 amendment](../decisions/0005-event-integrity-acceptance-and-recovery.md#gate-0-custodian-amendment-2026-11-18) names the planned Linux identity, initial directory-sync failure, read-only verify and enrollment checks for WB-CON-001/005/007/009 and WB-NEG-003/009. Implementation, activation prerequisites and target-specific test evidence are pending.

| Invariant | Constitutional link | Phase 1 status |
|---|---|---|
| WB-INV-001 | WB-CON-001 / WB-CON-002 | Runtime authority deferred |
| WB-INV-002 | WB-CON-002 / WB-CON-004 | Proposal schema/policy deferred |
| WB-INV-003 | WB-CON-005 | Capability enforcement deferred |
| WB-INV-004 | WB-CON-009 | Recovery policy deferred |
| WB-INV-005 | WB-CON-003 / WB-CON-006 | Isolated no-op verdict and state acceptance verified on x64-review. |
| WB-INV-006 | WB-CON-007 | Audit completeness deferred |
| WB-INV-007 | WB-CON-004 / WB-CON-005 / WB-CON-009 | Approval binding deferred |
| WB-INV-008 | WB-CON-008 | Duplicate/stale acceptance deferred |
| WB-INV-009 | WB-CON-001 / WB-CON-006 / WB-CON-008 | Authoritative projection deferred |
| WB-INV-010 | WB-CON-003 / WB-CON-006 | Learning/promotion unsupported and deferred |

Commands, platform separation, historical blocked gates and review findings are recorded in `docs/verification/phase1-evidence.md`. Ian's explicit Phase 1 acceptance is recorded in [ADR-0004](../decisions/0004-reproducible-odin-toolchain-and-ci.md), dated 2026-11-10, against `28cce613`.

The initial evidence is historical. Local platform pins, manifests, transport limits, and gate results are in `docs/verification/phase1-review-evidence.md`. Subsequent publication and hosted results are in `docs/verification/phase1-publication-evidence.md`. Their earlier Proposed/blocked dispositions are not rewritten as later run results.

For WB-P1-001/WB-P1-006, `28cce613` adds explicit-profile rejection in `tests/governance/test_toolchain_versions.py`, a stable installer OS diagnostic and the native workflow no-APT rejection step. All 26 Python controls pass locally, including Check A. Check B and hosted verification of that source remain pending; no new Linux pass is inferred. Foundation acceptance closes no runtime row or structural debt and supplies no dependency-recovery proof.

## Historical proposals for closure and Phase 2 design

`docs/governance/phase1-closure-plan.md` distinguishes the recorded publication/hosted/protection gates and explicit owner acceptance from remaining dependency recovery, runner and procedure-layering work. Completed technical checks do not themselves imply acceptance; the dated owner decision does.

`docs/decisions/0005-event-integrity-acceptance-and-recovery.md` maps proposed mechanisms and required future verification to the existing WB-CON, WB-INV and WB-NEG identifiers. At the time of this design draft the runtime rows were planned/deferred. No event store, protected head, capability consumption, observation/evaluation boundary, recovery process or replay implementation is added by this design draft.

On 2026-10-18, Proto became ADR-0005 decision owner and selected SQLite with a separate same-VM checkpoint custodian as the design direction. ADR-0005 records the trust limits and revised prepare/confirm protocol, chained custody history and unified crash/fault recovery table; `docs/engineering/phase2-entry-review.md` tracks the remaining entry gates. This direction concerns WB-CON-007/008, WB-INV-006/008/009 and WB-NEG-009; their implementation and verification status remains planned. The owner selected operator-only reconciliation for a missing pledged event. [ADR-0005 acceptance](../decisions/0005-event-integrity-acceptance-and-recovery.md) and the [entry review](../engineering/phase2-entry-review.md) govern current design and implementation scope; runtime durability and recovery evidence remains pending.

`docs/decisions/0006-hosted-linux-runner-compatibility.md` tracks the WB-P1-001/WB-P1-006 build-environment risk and required future compatibility evidence. The owner selected native Ubuntu 26.04 evaluation; the unpromoted candidate is recorded in `docs/verification/ubuntu2604-compatibility-evidence.md`. The required Ubuntu 24.04 profile and exact version/OS rejection remain in force.

`docs/decisions/0007-phase1-entrypoint-boundaries.md` is Accepted by the project owner against v0.0.0 / 8afe351 and records bounded E1 within the three levels. The candidate retains 21 Python controls and adds one bounded dependency control; the original five Odin tests remain. `docs/engineering/phase1-effect-composition-review.md` records the actual call/effect graph. Behavioral passes and structural review are separate; formal finding closure remains pending. Runtime requirements remain planned/deferred.

`docs/engineering/phase1-effect-semantics-options.md` preserves the historical WB-P1-008 owner decision comparison: two explicit qualifications, complete proposed procedure/effect maps and structural/behavioral regression requirements. It authorizes no implementation and changes no runtime requirement status.

## ADR-0005 contract-alignment candidate

The existing [integrity](../contracts/event-integrity.md), [state](../contracts/authoritative-state.md), [evaluation](../contracts/independent-evaluation.md) and [proposal](../contracts/model-proposals.md) contracts now express the proposed Phase 2 custody limits, full event identities, confirmed-prefix visibility, registered evidence and no-op scope. Trust/threat, package, pipeline and state documents link the single ADR specification instead of defining parallel schemas. This maps the design to WB-CON-001 through WB-CON-009, WB-INV-001 through WB-INV-009 and applicable WB-NEG-001 through WB-NEG-010/WB-NEG-012; every runtime implementation/evidence row remains planned. No constitutional or accepted ADR identifier changes.

[Phase 2 verification and finding disposition](phase2-verification-plan.md) provides the proposed proof groups for WB-CON-001 through WB-CON-009, WB-INV-001 through WB-INV-009 and applicable WB-NEG runtime cases. It separately records the three Phase 1 findings as named Proto-owned release debt, with explicit closure still pending. Runtime rows remain planned; existing foundation results are not reused as runtime proof.

Proto selected ADR-0005 Option A at Gate 1 on 2026-10-21, accepting unbounded aggregate denial-history growth as a Phase 2 limitation while preserving per-receipt bounds and fail-closed storage behavior. This records a design choice for WB-CON-007; no runtime verification status changes. ADR acceptance and Phase 2 entry remain separate Gates 2 and 3.
