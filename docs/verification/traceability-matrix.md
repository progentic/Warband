# Traceability Matrix

This matrix links constitutional rules to contracts, planned implementation, verification, and user-visible behavior.

| Requirement | Contract | Planned implementation | Planned verification | User behavior | Status |
|---|---|---|---|---|---|
| WB-CON-001 | `docs/contracts/authoritative-state.md` | `src/state/transition.odin` | `tests/invariants/no_direct_state_mutation_test.odin` | The AI cannot directly mark work complete. | planned |
| WB-CON-002 | `docs/contracts/model-proposals.md` | `src/gateway/` | `tests/negative/malformed_proposal_test.odin` | AI suggestions are checked before use. | planned |
| WB-CON-003 | `docs/contracts/independent-evaluation.md` | `src/evaluation/` | `tests/invariants/no_unverified_completion_test.odin` | Completion requires proof. | planned |
| WB-CON-004 | `docs/contracts/model-proposals.md` | `src/policy/` | `tests/invariants/policy_before_execution_test.odin` | Nothing runs without a policy decision. | planned |
| WB-CON-005 | `docs/contracts/model-proposals.md` | `src/capability/` | `tests/negative/capability_escalation_test.odin` | AI access is narrow and temporary. | planned |
| WB-CON-006 | `docs/contracts/authoritative-state.md` | `src/state/transition.odin` | `tests/invariants/evidence_backed_transition_test.odin` | State changes require recorded proof. | planned |
| WB-CON-007 | `docs/contracts/event-integrity.md` | `src/audit/` | `tests/invariants/audit_completeness_test.odin` | Important actions appear in activity history. | planned |
| WB-CON-008 | `docs/contracts/authoritative-state.md` | `src/state/replay.odin` | `tests/negative/duplicate_execution_test.odin` | Commands do not change state twice. | planned |
| WB-CON-009 | `docs/contracts/authoritative-state.md` | `src/recovery/` | `tests/negative/missing_recovery_policy_test.odin` | Unsafe actions stop before execution. | planned |
| WB-CON-010 | `docs/contracts/model-proposals.md` | `src/model/provider.odin` | `tests/integration/provider_independence_test.odin` | Safety does not depend on one AI provider. | planned |

## Phase 1 implementation evidence

The constitutional rows above remain planned. Foundation tests do not establish runtime authority, model isolation, evidence acceptance, or replay.

| Foundation requirement | Implementation | Verification | Status |
|---|---|---|---|
| WB-P1-001: pinned compiler | `toolchain/odin.lock.json`, `scripts/build_odin.sh`, `scripts/assert_toolchain.py` | Source HEAD, build-script digest, PATH/version/resources, LLVM version | verified locally on macOS ARM64 and Linux x64 |
| WB-P1-002: executable identity | `cmd/warband/`, `scripts/build_warband.sh`, `scripts/build_manifest.py` | Executable metadata and CLI smoke | ARM64 Mach-O and x64 ELF verified locally |
| WB-P1-003: explicit phase | `project.json`, `scripts/check_docs.py`, `scripts/governance.py`, `scripts/document_io.py` | Governance fixtures; WB-NEG-013/016 | locally verified |
| WB-P1-004: complete test execution | `tests/odin-packages.json`, `scripts/run_odin_tests.py`, `scripts/test_inventory.py` | Exact source/manifest/report inventory; WB-NEG-014 | 2 packages / 5 tests verified separately on macOS and Linux; 17 Python controls |
| WB-P1-005: VM preparation | `vm/lima.yaml`, `vm/selection.json` | Explicit development architecture; no mounts/forwarded application ports; image gate | original ARM profile pending; reviewed x64 verification VM provisioned |
| WB-P1-006: hosted CI | `.github/workflows/docs.yml`, `.github/workflows/phase1.yml` | actionlint, pinned actions, read-only token, credential-free checkout | inspected; publication authorized; hosted results pending |
| WB-P1-007: deterministic data | `src/domain/`, `src/fixture/` | Golden bytes, supplied IDs/tick, round trip, distinct types, WB-NEG-015 | verified locally on macOS and Linux |

## Invariant coverage status

| Invariant | Constitutional link | Phase 1 status |
|---|---|---|
| WB-INV-001 | WB-CON-001 / WB-CON-002 | Runtime authority deferred |
| WB-INV-002 | WB-CON-002 / WB-CON-004 | Proposal schema/policy deferred |
| WB-INV-003 | WB-CON-005 | Capability enforcement deferred |
| WB-INV-004 | WB-CON-009 | Recovery policy deferred |
| WB-INV-005 | WB-CON-003 / WB-CON-006 | Independent evaluation deferred |
| WB-INV-006 | WB-CON-007 | Audit completeness deferred |
| WB-INV-007 | WB-CON-004 / WB-CON-005 / WB-CON-009 | Approval binding deferred |
| WB-INV-008 | WB-CON-008 | Duplicate/stale acceptance deferred |
| WB-INV-009 | WB-CON-001 / WB-CON-006 / WB-CON-008 | Authoritative projection deferred |
| WB-INV-010 | WB-CON-003 / WB-CON-006 | Learning/promotion unsupported and deferred |

Commands, platform separation, blocked gates, and review findings are recorded in `docs/verification/phase1-evidence.md`. ADR-0004 remains Proposed; ownership and formal approval are outstanding.

The initial evidence is historical. Current platform pins, actual manifests, transport limits, and gate results are in `docs/verification/phase1-review-evidence.md`. Hosted CI and formal ADR acceptance remain unverified.

## Proposed closure and Phase 2 design

`docs/governance/phase1-closure-plan.md` records the remaining source-control, hosted evidence, dependency recovery, owner/review and branch-enforcement gates. These are planned actions, not newly passing checks.

`docs/decisions/0005-event-integrity-acceptance-and-recovery.md` maps proposed mechanisms and required future verification to the existing WB-CON, WB-INV and WB-NEG identifiers. The runtime rows above remain planned/deferred. No event store, protected head, capability consumption, observation/evaluation boundary, recovery process or replay implementation is added by this design draft.
