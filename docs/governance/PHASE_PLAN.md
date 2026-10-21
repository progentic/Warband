# Warband phase plan to v1.0.0

- **Status:** Proposed release roadmap
- **Planning baseline:** `main` at `3cbfd55b9157058cbd72dfcc6e14a59080925681`, published through `v0.0.2`; subsequent decision/tooling/contract/verification PRs remain candidates
- **Current implementation:** Phase 1 foundation complete
- **Target:** A narrow, evidence-backed production release tagged `v1.0.0`
- **Authority:** This document sequences work. It does not accept an ADR, select a production architecture, authorize a phase implementation, or declare a control verified.

## Purpose

Warband has a verified compiler, deterministic fixture, small CLI, governed documentation, hosted checks, retained run evidence, and protected integration path. It does not yet implement the production runtime described by the constitution.

This plan closes that gap without expanding into a general agent platform. Each phase must prove one additional trust boundary. A later phase cannot use planned work from an earlier phase as if it already exists.

The production objective is concrete:

1. Accept user intent and a typed proposal.
2. Decide policy before execution.
3. Bind any approval and issue a narrow capability.
4. Execute one reviewed action inside a controlled boundary.
5. Record observations and evaluate them independently.
6. Commit an authoritative transition at most once.
7. Rebuild the same state from the event history after restart.
8. Stop safely when authority, evidence, integrity, or recovery is uncertain.

## Recommended v1 product envelope

The following is the recommended scope because it proves the full control boundary with the smallest trusted core. It requires owner acceptance before implementation.

| Option | Shape | Benefit | Cost and risk | Recommendation |
|---|---|---|---|---|
| A | Single host, single writer, local durable store, CLI operator surface, one provider adapter, and one bounded reversible tool | Smallest review and recovery surface; directly exercises every constitutional boundary | Limited scale and tool breadth | **Recommended for v1.0.0** |
| B | Multiple runtime services with remote workers | Stronger process separation and future scale | Adds distributed identity, transport, ordering, and partial failure before the core is proven | Defer |
| C | General provider and tool framework | Broad early integration surface | Expands untrusted inputs and compatibility work faster than verification capacity | Reject for v1.0.0 |

Option A does not select an operating system version, CPU floor, store, sandbox mechanism, provider, or tool. Those choices require scoped decisions and matching evidence. CI artifacts are not production artifacts unless a later decision explicitly establishes that equivalence.

## Rules that apply to every phase

1. The [runtime constitution](../foundation/runtime-constitution.md) remains the highest authority.
2. Preserve accepted ADR-0001 through ADR-0003 and ADR-0007. Proposed ADRs remain non-authoritative until explicitly accepted.
3. A phase begins only after its design decisions, owner, scope, and implementation authorization are recorded.
4. A phase exits only when its user, engineering, security, and verification descriptions agree.
5. Every new permission or state transition needs a rejecting test. Test additions must satisfy the repository's test necessity rule.
6. Evidence must identify the exact source commit, toolchain, target, test inventory, and runner or host that produced it.
7. A passing model response, prompt, package boundary, or happy-path test is never proof of a security guarantee.
8. Unknown, malformed, stale, duplicate, unauthorized, expired, tampered, or unverifiable input fails closed.
9. Phase evidence is retained as reviewable data. Untrusted CI artifacts are not executed in a privileged environment.
10. Release tags are created only after the protected merge and release authorization.
11. A change to an accepted store, checkpoint custodian, execution boundary, production target, or evidence-producing trust boundary invalidates the affected phase evidence. The governing ADR and every dependent verification gate must be rerun before the change can be accepted.

## Foundation obligations carried to production

Phase 1 implementation is complete. The following open records do not require reopening its delivered code, but they block a production claim and must be resolved on the path to v1.0.0:

| Obligation | Current state | Accountable owner | Blocking gate | Required disposition |
|---|---|---|---|---|
| ADR-0004 ownership and status | Proposed; owner unassigned | Must be assigned before Phase 5 entry | Phase 5 entry | Accept, revise, supersede, or reject it with evidence |
| Dependency retention and recovery | Durable archive and clean restore test pending | Must be assigned before Phase 5 entry | Phase 5 exit | Select custody, preserve verified inputs, and pass a clean recovery build |
| Ubuntu 26.04 rejection evidence | Checks A and B authorized but not implemented | ADR-0006 decision owner | Phase 5 entry | Implement only the authorized checks and retain their separate negative evidence |
| Ubuntu 26.04 promotion | Directed after rollout completion; not implemented | ADR-0006 decision owner | Phase 5 entry | Use a separate PR with defined rollback, no automatic fallback, and unchanged required check names |
| ADR-0006 status | Proposed; owner recorded | ADR-0006 decision owner | Phase 5 entry | Review post-rollout evidence and explicitly accept, revise, supersede, or reject it |
| Phase 1 structural findings | Three source-reviewed E1 corrections; [named debts](../verification/phase2-verification-plan.md#phase-1-findings-disposition), explicit closure pending | Proto | Phase 2 entry requires the recorded debt alternative; binding closure deadline is Phase 5 entry; v1 remains blocked downstream | Review CLI, documentation and manifest finding dispositions separately; no closure inferred from builds |

These obligations may proceed in parallel with Phase 2 design. The named blocking gate is authoritative. Unresolved release debt must still satisfy the v1.0.0 release gates; a label does not waive the underlying control.

## Release sequence

| Phase | Intended version | Boundary proved | Exit result |
|---|---|---|---|
| 1 | `v0.0.x` | Reproducible governed foundation | Complete and published; production prerequisites above remain tracked |
| 2 | `v0.1.0` | Deterministic authority and event integrity | A no-op task can be authorized, evidenced, committed once, recovered, and replayed |
| 3 | `v0.2.0` | Controlled local execution | One bounded reversible action runs under an enforced capability and verified recovery policy |
| 4 | `v0.3.0` | Untrusted model and operator workflow | A real provider can propose, but cannot authorize, execute, evaluate itself, or commit state |
| 5 | `v0.4.0` | Production operations and release supply chain | The selected deployment can be installed, observed, upgraded, restored, and rolled back safely |
| 6 | `v1.0.0-rc.1` to `v1.0.0` | Exact release candidate | All constitutional, negative, recovery, security, and operational gates pass on the released source |

Version numbers are planning targets. The actual release entry and date are added only when publication is authorized.

## Phase 2–6 review and exit gate table

This table stages the existing phase requirements; it does not authorize implementation or accept an ADR. The preceding [reviewed baseline rules and foundation obligations](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/governance/PHASE_PLAN.md#L38-L65) already require named ownership, evidence identity and rejection tests. Detailed per-phase sections below remain authoritative. No provider, real tool, batching or remote custody work is authorized by the current documentation task.

| Phase / accountable owner | Entry gate | Deliverables | Required evidence / stable IDs | Exit gate |
|---|---|---|---|---|
| 2 / Proto, ADR-0005 owner | Explicitly accept the amended ADR and its exact schema/store/custodian/effect graph; align contracts; record the named Phase 1 debts or explicit closure; authorize the no-op implementation | Pure rules and codecs, project-local SQLite, same-VM custodian, one no-op authority path, operator enrollment/epoch handling, recovery and replay; follow [implementation slices](../verification/phase2-verification-plan.md#implementation-sequence-after-acceptance) | WB-CON-001 through WB-CON-009; scoped WB-INV-001 through WB-INV-009; WB-NEG-001, WB-NEG-003 through WB-NEG-010 and WB-NEG-012. Independent cross-platform vectors; actual UID denial; all durable boundaries; exact pledged versus fabricated-tail recovery; competing acceptors; deterministic replay. Approval evidence is rejection-only here | Accepted source/store/custody/target identity; no duplicate transition, fabricated completion or acknowledged audit loss; uncertain execution never redispatched. Complete scoped traceability and operator handoff; no real tool/provider |
| 3 / Proto; execution-boundary owner must be named before entry | Phase 2 exit accepted; execution ADR and one bounded reversible tool contract accepted; production host/CPU selected or target explicitly preproduction; local CLI approval semantics selected | Capability-enforced worker, network denial, bounded resources/filesystem/output, recorded CLI approval bound to exact proposal and Phase 2 identities, observation and recovery for the one selected action | WB-CON-001 through WB-CON-009 integrated; WB-INV-001 through WB-INV-009 including positive/mutated CLI approval. WB-NEG-002 through WB-NEG-006, WB-NEG-008, WB-NEG-010/011 real paths plus earlier applicable regressions. Actual worker outbound/local-network denial, escape/privilege/resource failures, crash/response-loss and no unsafe retry | Independently verified action and auditable failure/recovery on the declared kernel. CLI integration proof is mandatory, not replaced by harness tests. Preproduction evidence cannot substitute for Phase 5 production-target rerun |
| 4 / Proto; adapter/operator-workflow owner named before entry | Phase 3 exit accepted; provider projection/credential/retention/failure policy and separate scoped adapter egress reviewed; inherit accepted evaluator/approval identities without weakening them | One future provider adapter and operator presentation, strict normalization, redaction, bounded provider egress outside the network-denied worker; no broad integration framework | WB-CON-001 through WB-CON-010; WB-INV-001 through WB-INV-010; WB-NEG-001 through WB-NEG-012. Adversarial/malformed/stale/duplicate proposals, model success without evidence, changed provider, egress/credential/redaction rejection and exact approval binding. Learned promotion remains unsupported and rejecting | Live provider can propose only; deterministic fixtures reproduce authority/state results without provider access. Full negative-path coverage and no provider credential in the worker |
| 5 / Proto; name operations, dependency-recovery and security-triage owners plus independent reviewer before entry | Phase 4 exit accepted; exact production OS/CPU/kernel/VM/storage/service profile selected; resolve entry-blocking ADR-0004/0006, Ubuntu rejection/promotion disposition and named structural debts; retain accepted store/custodian or invalidate/rerun affected evidence | Locked production build/install/configuration, retained dependencies, backup/restore and custody reconciliation, operator epoch-change and migration/rollback runbooks, observability/redaction, release provenance and signing plan | WB-CON-001 through WB-CON-010; WB-INV-001 through WB-INV-010; real-path WB-NEG-001 through WB-NEG-012. Clean dependency rebuild; all production-target Phase 2 vectors/fault/replay and Phase 3 sandbox/network tests rerun when boundaries differ. Verify SQLite source/version/compile options/linkage on every supported target, Linux durability on the exact storage/VM profile, macOS development without durability claims. Rehearse empty-host restore with trusted head, operator epoch change and missing-pledge reconciliation, upgrade/rollback and interrupted recovery | Restore/upgrade/rollback demonstrated; independent security review; no open critical/high finding; residual risks owned and approved; dependency recovery proof complete. Record exact production artifact and evidence package |
| 6 / Proto as release decision authority; release executor and independent reviewer named before entry | Accepted Phase 5 exit and evidence; all foundation debt resolved at its gate; no unowned risks; explicit authorization to freeze exact RC commit | Frozen event/config/CLI/tool schemas, complete release manifest and durable evidence, operator procedures and exact RC build from retained inputs | WB-CON-001 through WB-CON-010, WB-INV-001 through WB-INV-010, WB-NEG-001 through WB-NEG-018 on the exact candidate as applicable. Complete workflow, target identity, independent review, install/task/rejection/backup/restore/epoch/reconciliation/rollback rehearsal; no skipped or substituted required test | All thirteen release gates below pass; explicit owner authorization for changelog, protected merge, annotated tag and publication. Any changed source/dependency/target/trust boundary creates a new candidate and affected reruns |

Every phase retains foundation WB-NEG-013 through WB-NEG-018 and required branch checks. Role names above are accountability/gates, not claims that independent people or future decisions are assigned. Proto must record the actual operations/security/release owners and independent reviewer before their entry gates. Current phase remains 1; version targets remain planning values. The current task creates no tag, release entry, service or production architecture.

### Operator acceptance handoff for Phase 2

Review the ADR amendment, static vectors, exact SQLite pin, enumerated effect graph, aligned contracts and [verification/finding plan](../verification/phase2-verification-plan.md) together. The operator must explicitly record acceptance or requested changes; neither merging documentation nor green foundation checks accepts ADR-0005. Then separately record Phase 2 entry against the exact approved source and authorize each implementation slice. A supported phase value in tooling is not an entry decision.

## Constitutional closure map

This map identifies the first phase that must produce evidence for each constitutional rule. A scoped pass does not replace later integrated or production-target verification.

| Phase | Required constitutional evidence |
|---|---|
| 2 | WB-CON-001 through WB-CON-009 on the deterministic no-op authority path |
| 3 | WB-CON-004 through WB-CON-009 on the bounded state-changing execution path; integrated regression of WB-CON-001 through WB-CON-003 |
| 4 | WB-CON-002 through WB-CON-005, WB-CON-007, and WB-CON-010 through the live provider and operator path; integrated regression of the remaining rules |
| 5 | WB-CON-001 through WB-CON-010 on the selected production target and deployment profile |
| 6 | WB-CON-001 through WB-CON-010 on the exact release candidate |

The traceability matrix must record the scoped status and evidence from each phase. A rule remains open for v1.0.0 until its Phase 5 and Phase 6 evidence exists.

## Phase 2: Deterministic authority core

### Outcome

Implement the smallest complete authority path using one deterministic no-op action. This phase proves that a proposal can pass through policy, capability, observation, evaluation, acceptance, audit, and replay without granting authority to the model or executor.

### Entry gates

- Assign an owner to [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md).
- Resolve and accept its event schema, payload registry, concrete storage backend, store durability, concrete protected-head custodian, crash-window behavior, task/control version rules, observer/evaluator trust, producer identity, and transaction boundaries.
- Treat the accepted storage backend and checkpoint custodian as part of the Phase 2 evidence identity. Changing either requires a new or amended ADR and invalidates the dependent Phase 2 fault, integrity, recovery, and replay evidence.
- Close the Phase 1 structural findings or record each one as named release debt under the foundation obligations table.
- Update the affected contracts, threat model, package boundaries, negative paths, and traceability before implementation.
- Record explicit Phase 2 implementation authorization.

### Required implementation

- Distinct task, run, proposal, capability, attempt, event, evidence, and transition identifiers.
- Canonical versioned event encoding with bounded payloads and independent golden vectors.
- One append-only event history with audit and authoritative projections.
- Independently trusted history checkpoint under documented threat assumptions.
- Proposal normalization and fingerprinting.
- Explicit policy and recovery decisions.
- Capability issuance, validation, one-use consumption, expiry, and revocation.
- Durable dispatch claim before the deterministic no-op.
- Trusted observation and independent deterministic evaluation.
- Expected-state and uniqueness checks in the acceptance transaction.
- Deterministic replay with no live model, tool, clock, policy reinterpretation, retry, or capability reissue.
- Typed, redacted errors and complete security event recording.

### Required verification

- Unit tests for pure encoders, decisions, transition rules, and projections.
- Golden encoding and hash vectors on Linux x64, macOS ARM64, and every additional architecture selected for Phase 2 acceptance. If the later production CPU architecture was not covered, Phase 5 must rerun the vectors and all target-dependent Phase 2 verification on that production target.
- Invariant tests for WB-INV-001 through WB-INV-009 within the no-op path.
- Applicable rejection tests from WB-NEG-001 and WB-NEG-003 through WB-NEG-010 and WB-NEG-012.
- Concurrent acceptance tests proving two acceptors cannot commit two valid transitions.
- Fault injection before and after every durable boundary in ADR-0005.
- Replay tests proving identical authoritative state from mixed accepted and rejected events.
- Integrity tests for alteration, reorder, truncation, head conflict, and whole-history replacement within the accepted threat model.

### Exit gate

Phase 2 exits only when the no-op path can be interrupted at every durable boundary, restarted, reconciled, and replayed against the accepted store and checkpoint custodian without duplicate execution, duplicate transition, fabricated completion, or loss of an acknowledged security event. The traceability rows for WB-CON-001 through WB-CON-009 and the exercised invariants and negative paths must change from `planned` to a scoped evidence-backed status. No external provider or state-changing tool is included.

## Phase 3: Controlled local execution

### Outcome

Replace the no-op with one owner-selected, bounded, reversible local action. Prove that authorization survives contact with a real execution boundary and an uncertain outcome.

### Entry gates

- Accept a dedicated execution-boundary ADR.
- Select the production operating system and CPU architecture for this phase's evidence, or explicitly classify the target as preproduction only.
- Define the tool contract, target scope, expected effect, observation source, resource limits, approval rule, idempotency rule, and recovery disposition.
- Define which sandbox controls are security requirements and how each is tested on the matching kernel.
- Select a minimal local CLI approval path for Phase 3. It must create a runtime-recorded approval bound to the exact normalized proposal and accepted Phase 2 identities. A deterministic test harness may exercise failure cases, but it cannot substitute for the CLI integration proof.

### Required implementation

- A worker boundary with explicit identity and authenticated runtime-to-worker requests.
- Default-deny tool registration. No arbitrary shell interface.
- Network access denied by default inside the worker. The Phase 3 action receives no network capability.
- Capability checks bound to action, target, arguments, task/run, attempt, expiry, use count, policy version, and expected state.
- Process, time, memory, output, and filesystem limits.
- Exact normalized-proposal binding for any human approval.
- Runtime-owned attempt identity and bounded observation capture.
- Redaction before persistence, model projection, logs, and user display.
- Typed uncertain-outcome handling. A timeout or lost response cannot prove that no effect occurred.
- Explicit compensation or operator reconciliation for the selected action.

### Required verification

- WB-NEG-002 through WB-NEG-006, WB-NEG-008, WB-NEG-010, and WB-NEG-011 on the actual execution path.
- Escape and privilege tests for every selected sandbox control.
- A rejecting test proving that the worker cannot open an outbound network connection or reach a disallowed local network endpoint.
- Resource exhaustion, oversized output, forced termination, worker crash, runtime crash, and response-loss tests.
- Duplicate dispatch and delayed-result tests proving no second authoritative transition.
- Approval mutation tests proving any payload or binding change invalidates approval.
- Recovery tests proving uncertain work is not automatically rerun.

### Exit gate

The selected action completes only from accepted evidence, never from executor output or a model claim. Every tested failure leaves an auditable disposition and a safe authoritative state. The local CLI approval and deterministic harness must use the same proposal-binding and acceptance semantics. Phase 4 may change presentation, but it may not weaken or reinterpret those semantics without invalidating Phase 3 approval evidence. Linux-specific claims must pass on the selected Linux target. macOS portability results cannot substitute for those claims.

## Phase 4: Model and operator workflow

### Outcome

Connect one reviewed model provider adapter and the operator approval workflow while keeping both outside the authority boundary.

### Entry gates

- Define the model input projection, data classification, retention rule, credential boundary, and provider failure policy.
- Define the supported typed proposal schema and size limits.
- Decide whether approval is local CLI only for v1.0.0. Any remote approval surface requires its own identity and transport review.
- Extend the accepted Phase 2 evaluator-independence, observer-trust, and producer-identity rules to the live provider path. Phase 4 must not define weaker replacement rules.
- Define provider egress as a separate, narrowly scoped adapter capability outside the execution worker. Record allowed destinations, protocols, credential use, time and response limits, and denial behavior. The Phase 3 worker remains network denied.

### Required implementation

- One provider adapter behind a provider-independent interface.
- Read-only, minimized, redacted model context.
- Strict parsing, normalization, schema versioning, and proposal fingerprinting.
- Operator inspection and approve/reject flow bound to the exact normalized proposal.
- Independent evaluator using runtime-owned success criteria and registered evidence sources.
- Provider timeout, cancellation, rate-limit, malformed-response, and retry controls.
- Provider egress restricted to the accepted destination and protocol set. Provider credentials never enter the execution worker.
- Audit events for proposal, normalization, policy, approval, execution, observation, evaluation, rejection, and transition.

### Required verification

- Adversarial proposal fixtures for malformed, unknown, oversized, stale, duplicate, and unauthorized requests.
- A model success claim without evidence cannot alter state.
- Provider changes or provider failure cannot change policy, capability, acceptance, or replay rules.
- Unexpected provider destinations and every network attempt from the execution worker are rejected and recorded.
- Approval cannot be reused for another task, run, attempt, target, payload, policy version, or expired request.
- Secret-bearing inputs and tool outputs are absent from provider requests, logs, audit payloads, errors, and user output unless a reviewed field policy explicitly permits them.
- All WB-NEG-001 through WB-NEG-012 have an implemented path and evidence by this phase's exit.

### Exit gate

An untrusted live provider can propose the selected action, but all authority remains in deterministic runtime controls. The same security and state results must be reproducible with deterministic proposal fixtures and without provider access. WB-CON-010 and WB-INV-010 require explicit evidence, even though learned promotion remains unsupported.

## Phase 5: Production operations and release supply chain

### Outcome

Turn the verified runtime into an operable, recoverable deployment without widening the v1 product envelope.

### Entry gates

- Select and document the production host, CPU floor, service boundary, installation method, and credential source.
- Close the named Proto-owned Phase 1 structural debts explicitly before Phase 5 entry.
- Confirm the Phase 2 storage backend and checkpoint custodian for production. A proposed change requires a new or amended ADR and reruns of all dependent Phase 2 evidence before Phase 5 work may rely on it.
- Resolve ADR-0004 and ADR-0006 or supersede them with accepted production decisions.
- Complete every foundation obligation whose blocking gate is Phase 5 entry. Confirm the dependency-retention owner, custody, inputs, and clean-restore procedure; the executed restore proof remains a Phase 5 exit requirement.
- Assign a release security triage owner and an independent reviewer for critical and high-severity findings.
- Define measurable availability, latency, resource, retention, backup, recovery, and audit-export requirements.

### Required implementation

- Locked production build profile separate from compatibility-only CI profiles.
- Versioned configuration with secure defaults and startup validation.
- Secret loading without command-line, log, crash-report, or artifact exposure.
- Schema migration with preflight, backup, failure recovery, and downgrade policy.
- Health, readiness, structured audit, metrics, and bounded diagnostic logging.
- Backup, restore, checkpoint reconciliation, and integrity verification procedures, including separately authorized epoch changes and operator-only missing-pledge reconciliation.
- Install, upgrade, rollback, and uninstall procedures.
- Resource and concurrency limits with operator-visible saturation behavior.
- Release manifest, software bill of materials, source and dependency provenance, checksums, and artifact signing.
- Security response, key rotation, evidence retention, and support procedures.

### Required verification

- Clean installation on the selected production target.
- Rerun the Phase 3 sandbox escape, privilege, resource, forced-termination, network-denial, uncertain-outcome, and applicable WB-NEG real-path suites on the exact production host and kernel. This is mandatory when Phase 3 used a preproduction target; the earlier evidence remains historical and cannot substitute.
- Rerun Phase 2 golden vectors and every target-dependent integrity, fault, recovery, and replay test when the production CPU, operating system, store, checkpoint custodian, or other evidence-producing trust boundary differs from the accepted Phase 2 environment.
- Backup and restore into an empty host with the same authoritative projection and verified head.
- Rehearse operator epoch changes and missing-pledge reconciliation, including interrupted installation, preserved prior evidence, rejected runtime-identity administration and no fabricated completion.
- Verify the exact SQLite source ID, compile options, connection settings and executable linkage on every supported target platform. Native macOS development validates functional behavior only; all Linux durability/permission claims require the matching Linux target.
- Rebuild from retained dependencies in a clean environment and complete the foundation recovery obligation.
- Upgrade from the immediately preceding published prerelease in the current release line and roll back after an injected migration failure. No older prerelease is supported for v1.0.0 unless a separate support policy explicitly names it. If no preceding prerelease exists, record that fact and use a clean-install migration baseline.
- Restart and power-loss tests around each durable boundary.
- Load and resource-limit tests against the declared operating envelope.
- Log, artifact, crash, and audit redaction review.
- Release artifact architecture, linkage, provenance, checksum, signature, and smoke verification.
- Independent threat-model and security review with every control linked to implementation and evidence.

### Exit gate

An operator can install, configure, start, stop, inspect, back up, restore, upgrade, and roll back Warband using reviewed procedures. The selected production artifact is built and tested on its declared target. No unresolved critical or high-severity security finding remains. Accepted residual risks are named, owned, and documented.

## Release finding severity and review

| Severity | Release meaning |
|---|---|
| Critical | A credible path to unauthorized execution or authoritative state change, secret compromise, audit-history trust loss, or release artifact compromise |
| High | A realistic bypass or material weakening of policy, capability, sandbox, approval, evidence, replay, recovery, or production-target enforcement |
| Medium | A bounded correctness, reliability, or operational defect without a demonstrated authority-boundary bypass |
| Low | A minor defect, usability issue, or documentation gap with no material control impact |

The assigned security triage owner records severity and release impact. The author of a finding or fix cannot be the only person to close a critical or high finding; the assigned independent reviewer must confirm the evidence and disposition. Critical and high findings block Phase 5 exit and v1.0.0. Medium and low residual risks require a named owner and explicit project-owner acceptance or a scheduled corrective disposition.

## Phase 6: Release candidate and v1.0.0

### Outcome

Freeze one exact candidate and prove that the released source, artifact, documentation, and operational procedures describe the same system.

### Entry gates

- Record Phase 5 exit with the exact production target, artifact identity, evidence package, accepted residual risks, and independent security review.
- Resolve every foundation obligation at its named blocking gate. No unowned release debt may enter the candidate.
- Confirm that no critical or high finding is open and every medium or low residual risk has the required owner and disposition.
- Obtain project-owner authorization to freeze one exact source commit as `v1.0.0-rc.1`.

### Release candidate rules

- Freeze the runtime event format, configuration schema, CLI surface, tool contract, and supported deployment profile.
- Add no feature after `v1.0.0-rc.1`. Only release-blocking corrections may enter the candidate line.
- Run the complete required workflow on the exact candidate commit and preserve durable evidence outside routine 30-day artifacts.
- Rebuild from the retained dependency set in a clean environment.
- Rehearse installation, one successful task, each principal rejection class, backup, restore, upgrade, rollback, and audit export.
- Review the final diff from the last prerelease, including generated release metadata and dependency changes.

### Required verification

The release candidate rules above define the Phase 6 verification procedure. Execute them against the exact frozen commit and selected production target, then satisfy every v1.0.0 release gate below. Evidence from a different commit, compatibility profile, operating system, CPU, store, checkpoint custodian, worker boundary, or provider path cannot be silently attributed to the candidate.

### v1.0.0 release gates

All of the following must be true:

1. WB-CON-001 through WB-CON-010 have accepted contracts, implemented controls, passing evidence, and current traceability rows.
2. WB-INV-001 through WB-INV-010 pass against the release candidate.
3. WB-NEG-001 through WB-NEG-012 pass on their applicable real paths on the selected production target. Phase 1 controls WB-NEG-013 through WB-NEG-018 remain passing on the exact release commit.
4. No required test is missing, skipped, unexpectedly absent, or replaced by a weaker substitute.
5. Replay from the accepted event history reproduces the authoritative projection without live I/O or policy reinterpretation.
6. Crash and uncertain-outcome tests show no unauthorized redispatch or duplicate transition.
7. The selected production architecture, dependency recovery path, release artifact, and rollback procedure are verified.
8. Required branch checks pass on the exact release commit and branch protection remains effective.
9. The security, threat, trust, architecture, contracts, operator guidance, negative paths, and traceability records agree with the implementation.
10. Every foundation obligation is resolved at its named gate, including the Ubuntu 26.04 rejecting checks, promotion disposition, and Phase 1 structural findings. No unowned release debt remains.
11. Every accepted ADR and release exception has an owner. No blocking Proposed decision is being treated as accepted.
12. Durable release evidence identifies source, toolchain, dependencies, target, artifact, tests, and approvals.
13. The project owner explicitly authorizes the changelog entry, protected merge, annotated `v1.0.0` tag, and publication.

Passing CI alone does not satisfy this gate. A release decision must cite the exact evidence and accepted residual risks.

### Exit gate

Phase 6 exits only after all thirteen release gates pass against the exact candidate, the independent release review is recorded, and the project owner authorizes publication. The protected merge commit must be the source of the annotated `v1.0.0` tag. Any post-review code, dependency, configuration, target, or trust-boundary change creates a new candidate and requires the affected verification to run again.

## Required evidence package for each phase

Each phase handoff must contain:

- exact source commit and reviewed diff range;
- accepted decisions and named owners;
- changed WB-CON, WB-INV, WB-NEG, and phase requirement mappings;
- complete test inventory with named results and negative evidence;
- toolchain, dependency, runner/host, target, and artifact identities;
- unresolved findings separated by severity and release impact;
- migration, recovery, rollback, and compatibility disposition;
- user-visible behavior and safe failure examples;
- explicit non-goals and deferred work;
- owner authorization for the next phase.

## v1.0.0 non-goals

The first production release does not include:

- arbitrary shell access;
- broad network access or an unrestricted connector framework;
- multiple concurrent authoritative writers;
- distributed consensus or automatic failover;
- a web interface;
- general multi-agent collaboration;
- model-authored policy or security rules;
- learned-pattern promotion;
- unsupervised irreversible actions;
- automatic fallback to an unverified toolchain, host, provider, store, or execution profile;
- a claim that external side effects are exactly once.

These items require later plans and separate authority. They must not enter v1.0.0 as incidental implementation details.

## Governance review provenance

The initial **conditionally aligned** disposition is recorded in [PR #7](https://github.com/progentic/Warband/pull/7). This link provides review provenance; this plan does not approve itself. The reviewed sequence preserves the constitution and accepted ADRs, keeps the model outside the trusted authority core, and requires evidence before state change. Production readiness remains blocked until the foundation obligations are closed, ADR-0005 is accepted, each later phase receives explicit authorization, and the v1.0.0 release gates have exact evidence.

No constitutional identifier is changed by this plan. The plan adds no implementation claim, so the current `planned` runtime rows in the [traceability matrix](../verification/traceability-matrix.md) remain correct until code and verification exist.
