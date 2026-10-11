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
