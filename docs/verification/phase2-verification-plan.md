# Phase 2 verification and finding disposition

- **Status:** Proposed verification plan; no runtime results
- **Accountable owner:** Proto, ADR-0005 decision owner
- **Source baseline:** `3cbfd55b9157058cbd72dfcc6e14a59080925681`; staged decision/tooling/contract PRs are separate review inputs
- **Implementation gate:** Explicit ADR-0005 acceptance and recorded Phase 2 entry; this document grants neither

## Evidence baseline and test necessity

[ADR-0005 baseline lines 188–211](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/decisions/0005-event-integrity-acceptance-and-recovery.md#L188-L211) already requires future identity, evidence, concurrency, integrity, crash and replay proofs. The [negative catalog lines 5–16](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/verification/negative-path-catalog.md#L5-L16) defines the stable runtime negative IDs. Foundation tests do not supply those proofs; the [traceability baseline lines 5–16](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/verification/traceability-matrix.md#L5-L16) marks runtime rows planned.

Each group below identifies a concrete requirement/failure, an uncovered runtime path, its expected value and its verification cost. This is submitted for operator review under the test-necessity rule; it is not a quota or authorization for extra permutations. Add only cases that distinguish a named decision or durable boundary. Retain existing controls and exact test inventory; report missing/skipped tests as failure.

## Required proof groups

| Group / concrete uncertainty | Gap and expected proof | IDs | Cost and evidence |
|---|---|---|---|
| Identity and tuple binding: changed store/epoch/sequence or one field in an idempotent request could be accepted as the same request | No custody implementation exists. Prove exact pending/latest-committed replay returns the original receipt without another frame; changed tuples, stale epochs and cross-scope references reject; an old committed replay cannot clear a later pending pledge | WB-CON-001/007/008; WB-INV-001/006/008/009; WB-NEG-005/006/009 | Deterministic pure-rule cases and real protocol transcripts; no new service/dependency |
| Canonical encoding: host layout, omitted fields or alternative parsing could change hashes | Independently reproduce the ADR's static event/link/frame/head vectors from the written field tables, then compare the future Odin codec; reject unknown schema/kind/producer, trailing bytes, malformed lengths and over-limit payloads | WB-CON-007/008; WB-INV-006/009; WB-NEG-001/012 | Linux x64/macOS ARM64 and any acceptance target; retain exact bytes, hashes, independent recipe/tool versions; do not regenerate expected bytes through the codec under test |
| Custody frame recovery: incomplete final write could be mistaken for valid corruption repair | Classify truncated final header/body/checksum separately from complete bad hashes, broken interior links and unexplained published heads; no scan-forward repair, no history rebuild from SQLite | WB-CON-007/008/009; WB-INV-004/006/008; WB-NEG-009 | Bounded independent damaged byte samples, tied to the actual frame parser and persisted files |
| Policy/capability: a permit could outlive its scope or be consumed twice | Exact proposal/criteria/recovery binding; reject missing recovery, expired/revoked/used lease, current-policy/task/control drift and approval-required requests; persist one claim/use before dispatch | WB-CON-004/005/009; WB-INV-002/003/004/007; WB-NEG-003/004/005/008/010 | Pure decision cases plus real transaction rejection evidence. Phase 2 approval evidence is rejection-only; a valid CLI approval path is a Phase 3 gate |
| Observer/evaluator provenance: a success claim or altered observation could become completion | Reject model success text, unknown role/version, substituted digest, cross-attempt references, incomplete criterion and indeterminate observation; only the state boundary accepts a verified no-op | WB-CON-001/002/003/006; WB-INV-001/005/009; WB-NEG-007 | Independent observation/evaluation cases and API/dependency review; do not claim resistance to compromise of the same trusted process |
| Durable ordering and visibility: acknowledgment or completion might escape before custody durability | Inject process failure at every boundary below; verify exact state, withheld output/dispatch, custodian receipts and confirmed-prefix reads after restart | WB-CON-006/007/008/009; WB-INV-004/005/006/008/009 | Real Linux processes, selected filesystem/VFS/VM flush configuration and source/build identities. Process kill alone does not prove power-loss behavior |
| OS custody: runtime identity might reach protected files or operator operations | Runtime UID cannot write/read restricted custody files as configured, replace protected parents/socket, enroll, change epochs or impersonate the custodian; authorized operator UID is distinct; actual denied operations supplement ownership/mode/ACL checks | WB-CON-001/005/007; WB-INV-001/003/006; WB-NEG-003/009 | Linux guest with separate UIDs and connected socket credentials. macOS tests are not substitute Linux security evidence; no deployment service is introduced by this plan |
| Concurrent acceptance: two acceptors might create two valid transitions | Competing processes target the same eligible versions/attempt and encounter the real lock and SQL constraints; exactly one eligible transition is confirmed; duplicate requests return the same recorded result | WB-CON-006/008; WB-INV-008/009; WB-NEG-005/006 | Matching SQLite build and real transactions; retain results, event counts and full identities rather than mock-only success |
| Replay: live state or current policy could alter historical results | Replay mixed accepted/rejected/revoked/indeterminate events to identical task/control projections; reject missing references, altered/truncated/reordered/replaced history against custody; no clock/model/tool, retry or lease reissue | WB-CON-001/006/007/008; WB-INV-006/008/009; WB-NEG-005/006/009/012 | Independent expected projection and deterministic replay with external operations unavailable; no provider integration |
| Operator enrollment/recovery: a reset could hide corruption or reuse authorization | Empty-store enrollment only; authorization unique and bound to exact old/new epoch/checkpoint/reason/pending receipt; old evidence retained; missing pledge remains operator-only; no automatic cancellation or completion carry-forward | WB-CON-001/006/007/008/009; WB-INV-004/006/008/009; WB-NEG-006/009 | Operator runbook rehearsal, audit receipts and interrupted epoch-installation states; future implementation, not executed here |

The stable identifiers are unchanged. WB-INV-007 receives only scoped rejection evidence in Phase 2; positive exact-payload CLI approval must pass in Phase 3. WB-INV-010 learned promotion stays unsupported, and Phase 4 must prove its rejection. WB-CON-010 is not claimed from a no-provider foundation. Scope every report accordingly.

## Durable-boundary crash checklist

Use ADR-0005's unified recovery table as the expected oracle; do not create a divergent recovery policy here. For each point record before/after durable files, SQLite visible/confirmed prefix, custody pending/committed state, named fault, automatic versus operator disposition, and whether any acknowledgment/dispatch occurred:

1. Before prepare and during the final PENDING frame write/fsync.
2. After durable prepare but before SQLite commit: `PENDING_EVENT_MISSING`, operator-only, no cancellation.
3. During SQLite transaction/commit; distinguish absent event from exact pledged event after restart.
4. After exact SQLite commit but before confirm: `PENDING_CONFIRMATION`, resume confirmation only after full binding validation.
5. During COMMITTED frame append/fsync and after its complete durable record, before head publication.
6. During head temporary write/file fsync, rename and directory fsync, then before the confirm reply.
7. After durable confirmation and before result acknowledgment; lost replies return original receipts/results, never another transition.
8. At the dispatch gate and after no-op return but before durable observation. A confirmed claim alone never proves whether execution occurred; recover indeterminate and do not redispatch.
9. During observation, evaluation and accepted-transition recording, applying the same prepare/commit/confirm boundary to each event.
10. During administrative genesis/epoch recording and installation; stop rather than synthesize an old head or carry untrusted facts.

Also inject ENOSPC/write/fsync errors, corrupt complete records and replace journal content independently of custody. Distinguish process crash, OS crash and simulated power loss in evidence; require the matching target proof before claiming each durability class. A documented trusted-kernel/root assumption is not a passing attack test.

## Implementation sequence after acceptance

| Slice | Deliverable | Prerequisite and review gate |
|---|---|---|
| 1 | Distinct full identities, bounded immutable values, pure prepare/confirm/recovery decisions | Accepted ADR wire/types, reviewed focused tests; no I/O handles in Mid |
| 2 | Event/custody codecs and hash domains | Independent vectors reproduced before comparing codec output; negative decoding and cross-platform evidence |
| 3 | Custodian local authentication, durable metadata and operator-only administration | Enumerated High graph; actual UID/file/socket denial; frame/head fault checks |
| 4 | Exact project-local SQLite build and pledged event append | Source/provenance/link checks on both development platforms; real Linux ordering/visibility evidence |
| 5 | One no-op policy/capability/observation/evaluation/acceptance path | Real bindings, constraints, no approval-required permit; concurrent acceptor rejection |
| 6 | Recovery, deterministic replay and phase exit package | Every durable boundary, named faults, operator reconciliation rehearsal, exact source/target/test inventory and scoped traceability |

These are reviewable implementation slices, not new frameworks or permission to omit later proofs. A passing codec or mocked custodian cannot close Phase 2.

## Phase 1 findings disposition

The original three findings and their separate closure gate are recorded in [closure-plan baseline lines 25–35](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/governance/phase1-closure-plan.md#L25-L35). [ADR-0007 lines 3–29](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/decisions/0007-phase1-entrypoint-boundaries.md#L3-L29) accepts only the enumerated Phase 1 E1 scope. Source review below is independent of build success.

| Named finding / accountable owner | Actual reviewed call path and evidence | Technical disposition | Administrative/release disposition |
|---|---|---|---|
| CLI acquisition/parsing / Proto | [main.odin lines 32–57](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/cmd/warband/main.odin#L32-L57): High main acquires arguments through Low, invokes supplied-value Mid parse/presentation, then Low output/exit. [Lines 75–93](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/cmd/warband/main.odin#L75-L93) contain the technical operations | Corrected under accepted scoped E1; no supplied-value parser I/O found | Named release debt awaiting Proto's explicit closure; binding deadline is Phase 5 entry; v1 release remains blocked downstream |
| Documentation acquisition/validation/reporting / Proto | [check_docs.py lines 7–17](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/check_docs.py#L7-L17): High main sequences acquisition, pure validation/status, reporting and exit. [Reviewed graph lines 21–66](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/engineering/phase1-effect-composition-review.md#L21-L66) maps the pure/effectful descendants | Corrected under E1; the new Phase 2 governance rule also remains pure and is included in the current graph | Named release debt awaiting Proto's explicit closure; same binding Phase 5 entry deadline |
| Manifest mixed technical/policy work / Proto | [build_manifest.py lines 16–54](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/build_manifest.py#L16-L54): validate platform -> acquire identity -> validate architecture/machine -> inspect linkage/provenance -> pure construct -> publish. [manifest_rules.py lines 77–84](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/manifest_rules.py#L77-L84) contains the pure coordinator; [manifest_io.py lines 34–93](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/scripts/manifest_io.py#L34-L93) contains technical adapters | Corrected under E1; architecture checks precede linkage and publication follows validation | Named release debt awaiting Proto's explicit closure; same binding Phase 5 entry deadline. Interrupted-write durability is not part of this correction |

A comparison against v0.0.0 / `8afe3512da88fe55e6ca1b919a1bd5d0b931baab` found no changes in those three entrypoints, manifest rules or manifest I/O sources. The [existing E1 evidence lines 57–96](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/verification/phase1-entrypoint-evidence.md#L57-L96) binds earlier functional/structural results to its exact source and platforms. This review recommends closure but does not infer an owner closure decision. Naming/owning debt is the phase plan's permitted alternative, not proof of security or overall Phase 1 acceptance. No new security severity is assigned by this architectural disposition.

### Ownership, severity and independent review

Proto owns remediation and the ADR decision; that accountability is not an independent closure review. No debt is closed here and no independent-review requirement is represented as satisfied. Severity and an independent reviewer remain unassigned. Before closure, the assigned security triage owner must record severity and impact under the [phase plan's review rule](../governance/PHASE_PLAN.md#release-finding-severity-and-review). Critical/high closure requires confirmation by the named independent reviewer, who cannot be the sole author of the finding or fix. Medium/low disposition follows the recorded project-owner acceptance or corrective schedule rule. Proto's ownership alone supplies neither severity nor independence.

The binding deadline for all three debts is **Phase 5 entry**. The v1 release gate is a downstream backstop, not an alternative later deadline. Failure to close a debt prevents Phase 5 entry even if v1 publication is far away. The Phase 2 entry alternative records named debt and ownership; it does not waive these closure conditions or allow self-approval of a critical/high finding.

## Present results versus future proofs

The design-only candidate has passing documentation governance and 25 Python controls (22 existing plus three targeted governance-tooling controls). The revised native macOS runner executed the original two Odin packages/five named tests. Static vector hash calculations were cross-checked with OpenSSL; SQLite archive/source digests matched upstream. No runtime codec, custodian, SQLite binding, authority path, privilege test, fault injection or replay suite exists yet. Hosted foundation runs on each review PR are regression evidence for their tested commit, not runtime proof. Record final PR heads and actual hosted outcomes in the handoff.
