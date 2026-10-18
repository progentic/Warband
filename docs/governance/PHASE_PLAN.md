# Warband phase plan to v1.0.0

- **Status:** Proposed release roadmap
- **Planning baseline:** `main` at `75af4a65482e722b4e567ade12292a2ba800fe92`, published through `v0.0.2`
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

## Foundation obligations before Phase 2 implementation

Phase 1 implementation is complete. The following open records do not require reopening its delivered code, but they block a production claim and must be resolved on the path to v1.0.0:

| Obligation | Current state | Required disposition |
|---|---|---|
| ADR-0004 ownership and status | Proposed; owner unassigned | Assign an owner and accept, revise, supersede, or reject it with evidence |
| Dependency retention and recovery | Durable archive and clean restore test pending | Select custody, preserve verified inputs, and pass a clean recovery build |
| Ubuntu 26.04 rejection evidence | Checks A and B authorized but not implemented | Implement only the authorized checks and retain their separate negative evidence |
| Ubuntu 26.04 promotion | Directed after rollout completion; not implemented | Use a separate PR with defined rollback, no automatic fallback, and unchanged required check names |
| ADR-0006 status | Proposed; owner recorded | Review post-rollout evidence and explicitly accept, revise, supersede, or reject it |
| Phase 1 structural findings | ADR-0007 accepted; formal finding closure remains separate | Record explicit closure against the reviewed E1 implementation or retain the findings as release debt |

These obligations may proceed in parallel with Phase 2 design. Phase 2 runtime code must not begin until ADR-0005 and its blocking choices are resolved.

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

## Phase 2: Deterministic authority core

### Outcome

Implement the smallest complete authority path using one deterministic no-op action. This phase proves that a proposal can pass through policy, capability, observation, evaluation, acceptance, audit, and replay without granting authority to the model or executor.

### Entry gates

- Assign an owner to [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md).
- Resolve and accept its event schema, payload registry, store durability, protected-head custody, crash-window behavior, task/control version rules, observer/evaluator trust, and transaction boundaries.
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
- Golden encoding and hash vectors on Linux x64 and macOS ARM64.
- Invariant tests for WB-INV-001 through WB-INV-009 within the no-op path.
- Applicable rejection tests from WB-NEG-001 and WB-NEG-003 through WB-NEG-010 and WB-NEG-012.
- Concurrent acceptance tests proving two acceptors cannot commit two valid transitions.
- Fault injection before and after every durable boundary in ADR-0005.
- Replay tests proving identical authoritative state from mixed accepted and rejected events.
- Integrity tests for alteration, reorder, truncation, head conflict, and whole-history replacement within the accepted threat model.

### Exit gate

Phase 2 exits only when the no-op path can be interrupted at every durable boundary, restarted, reconciled, and replayed without duplicate execution, duplicate transition, fabricated completion, or loss of an acknowledged security event. The traceability rows for the exercised scope must change from `planned` to evidence-backed status. No external provider or state-changing tool is included.

## Phase 3: Controlled local execution

### Outcome

Replace the no-op with one owner-selected, bounded, reversible local action. Prove that authorization survives contact with a real execution boundary and an uncertain outcome.

### Entry gates

- Accept a dedicated execution-boundary ADR.
- Select the production operating system and CPU architecture for this phase's evidence, or explicitly classify the target as preproduction only.
- Define the tool contract, target scope, expected effect, observation source, resource limits, approval rule, idempotency rule, and recovery disposition.
- Define which sandbox controls are security requirements and how each is tested on the matching kernel.

### Required implementation

- A worker boundary with explicit identity and authenticated runtime-to-worker requests.
- Default-deny tool registration. No arbitrary shell interface.
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
- Resource exhaustion, oversized output, forced termination, worker crash, runtime crash, and response-loss tests.
- Duplicate dispatch and delayed-result tests proving no second authoritative transition.
- Approval mutation tests proving any payload or binding change invalidates approval.
- Recovery tests proving uncertain work is not automatically rerun.

### Exit gate

The selected action completes only from accepted evidence, never from executor output or a model claim. Every tested failure leaves an auditable disposition and a safe authoritative state. Linux-specific claims must pass on the selected Linux target. macOS portability results cannot substitute for those claims.

## Phase 4: Model and operator workflow

### Outcome

Connect one reviewed model provider adapter and the operator approval workflow while keeping both outside the authority boundary.

### Entry gates

- Define the model input projection, data classification, retention rule, credential boundary, and provider failure policy.
- Define the supported typed proposal schema and size limits.
- Decide whether approval is local CLI only for v1.0.0. Any remote approval surface requires its own identity and transport review.
- Record the evaluator's independence and producer identity rules.

### Required implementation

- One provider adapter behind a provider-independent interface.
- Read-only, minimized, redacted model context.
- Strict parsing, normalization, schema versioning, and proposal fingerprinting.
- Operator inspection and approve/reject flow bound to the exact normalized proposal.
- Independent evaluator using runtime-owned success criteria and registered evidence sources.
- Provider timeout, cancellation, rate-limit, malformed-response, and retry controls.
- Audit events for proposal, normalization, policy, approval, execution, observation, evaluation, rejection, and transition.

### Required verification

- Adversarial proposal fixtures for malformed, unknown, oversized, stale, duplicate, and unauthorized requests.
- A model success claim without evidence cannot alter state.
- Provider changes or provider failure cannot change policy, capability, acceptance, or replay rules.
- Approval cannot be reused for another task, run, attempt, target, payload, policy version, or expired request.
- Secret-bearing inputs and tool outputs are absent from provider requests, logs, audit payloads, errors, and user output unless a reviewed field policy explicitly permits them.
- All WB-NEG-001 through WB-NEG-012 have an implemented path and evidence by this phase's exit.

### Exit gate

An untrusted live provider can propose the selected action, but all authority remains in deterministic runtime controls. The same security and state results must be reproducible with deterministic proposal fixtures and without provider access. WB-CON-010 and WB-INV-010 require explicit evidence, even though learned promotion remains unsupported.

## Phase 5: Production operations and release supply chain

### Outcome

Turn the verified runtime into an operable, recoverable deployment without widening the v1 product envelope.

### Entry gates

- Select and document the production host, CPU floor, service boundary, storage backend, checkpoint custodian, installation method, and credential source.
- Resolve ADR-0004 and ADR-0006 or supersede them with accepted production decisions.
- Complete dependency retention and the clean restore proof.
- Define measurable availability, latency, resource, retention, backup, recovery, and audit-export requirements.

### Required implementation

- Locked production build profile separate from compatibility-only CI profiles.
- Versioned configuration with secure defaults and startup validation.
- Secret loading without command-line, log, crash-report, or artifact exposure.
- Schema migration with preflight, backup, failure recovery, and downgrade policy.
- Health, readiness, structured audit, metrics, and bounded diagnostic logging.
- Backup, restore, checkpoint reconciliation, and integrity verification procedures.
- Install, upgrade, rollback, and uninstall procedures.
- Resource and concurrency limits with operator-visible saturation behavior.
- Release manifest, software bill of materials, source and dependency provenance, checksums, and artifact signing.
- Security response, key rotation, evidence retention, and support procedures.

### Required verification

- Clean installation on the selected production target.
- Backup and restore into an empty host with the same authoritative projection and verified head.
- Upgrade from the latest supported prerelease and rollback after an injected migration failure.
- Restart and power-loss tests around each durable boundary.
- Load and resource-limit tests against the declared operating envelope.
- Log, artifact, crash, and audit redaction review.
- Release artifact architecture, linkage, provenance, checksum, signature, and smoke verification.
- Threat-model review with every control linked to implementation and evidence.

### Exit gate

An operator can install, configure, start, stop, inspect, back up, restore, upgrade, and roll back Warband using reviewed procedures. The selected production artifact is built and tested on its declared target. No unresolved critical or high-severity security finding remains. Accepted residual risks are named, owned, and documented.

## Phase 6: Release candidate and v1.0.0

### Outcome

Freeze one exact candidate and prove that the released source, artifact, documentation, and operational procedures describe the same system.

### Release candidate rules

- Freeze the runtime event format, configuration schema, CLI surface, tool contract, and supported deployment profile.
- Add no feature after `v1.0.0-rc.1`. Only release-blocking corrections may enter the candidate line.
- Run the complete required workflow on the exact candidate commit and preserve durable evidence outside routine 30-day artifacts.
- Rebuild from the retained dependency set in a clean environment.
- Rehearse installation, one successful task, each principal rejection class, backup, restore, upgrade, rollback, and audit export.
- Review the final diff from the last prerelease, including generated release metadata and dependency changes.

### v1.0.0 release gates

All of the following must be true:

1. WB-CON-001 through WB-CON-010 have accepted contracts, implemented controls, passing evidence, and current traceability rows.
2. WB-INV-001 through WB-INV-010 pass against the release candidate.
3. WB-NEG-001 through WB-NEG-012 pass on their applicable real paths. Phase 1 controls WB-NEG-013 through WB-NEG-018 remain passing.
4. No required test is missing, skipped, unexpectedly absent, or replaced by a weaker substitute.
5. Replay from the accepted event history reproduces the authoritative projection without live I/O or policy reinterpretation.
6. Crash and uncertain-outcome tests show no unauthorized redispatch or duplicate transition.
7. The selected production architecture, dependency recovery path, release artifact, and rollback procedure are verified.
8. Required branch checks pass on the exact release commit and branch protection remains effective.
9. The security, threat, trust, architecture, contracts, operator guidance, negative paths, and traceability records agree with the implementation.
10. Every accepted ADR and release exception has an owner. No blocking Proposed decision is being treated as accepted.
11. Durable release evidence identifies source, toolchain, dependencies, target, artifact, tests, and approvals.
12. The project owner explicitly authorizes the changelog entry, protected merge, annotated `v1.0.0` tag, and publication.

Passing CI alone does not satisfy this gate. A release decision must cite the exact evidence and accepted residual risks.

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

## Governance review disposition

**Verdict: conditionally aligned.** The sequence preserves the constitution and accepted ADRs, keeps the model outside the trusted authority core, and requires evidence before state change. Production readiness remains blocked until the foundation obligations are closed, ADR-0005 is accepted, each later phase receives explicit authorization, and the v1.0.0 release gates have exact evidence.

No constitutional identifier is changed by this plan. The plan adds no implementation claim, so the current `planned` runtime rows in the [traceability matrix](../verification/traceability-matrix.md) remain correct until code and verification exist.
