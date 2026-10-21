# State Model

Warband keeps one append-only event history and derives different views from it.

## Audit projection

The audit projection includes everything that happened:

- proposals;
- rejections;
- approvals;
- execution attempts;
- failures;
- evaluator results;
- committed transitions.

This view supports debugging, security review, retry control, and incident analysis.

## Authoritative projection

The authoritative projection includes only verified, policy-authorized facts that are allowed to change system state.

A model claim may appear in the audit projection. It cannot appear as an authoritative fact unless an independent evaluator produced acceptable evidence and the state-transition boundary accepted it.

## Pre-state checks

Every state-changing transition must verify that the current state still matches the state expected when the action was authorized. Stale results must be rejected.

## Phase 2 version and visibility candidate

The [ADR-0005 transition table](../decisions/0005-event-integrity-acceptance-and-recovery.md#4-versions-and-acceptance-table) distinguishes event ordering, task version, control revision and immutable attempt identity. Event references include store/epoch/sequence, and all task/control lookups include store/epoch. Replay checks reference closure and uniqueness before applying eligible facts. Task/control evidence has explicit schema and producing events; a model claim remains audit-only.

The authoritative read boundary is the custodian-confirmed prefix, not SQLite's latest committed row. A pending local commit is diagnostic data until confirmation. Epoch administration preserves old segments and does not carry untrusted task facts into a new epoch. The Phase 2 candidate does not implement any of these projections.
