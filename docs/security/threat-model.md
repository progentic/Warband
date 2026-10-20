# Threat Model

This document lists the first threats Warband must address.

## Threat: model fabricates success

Control: independent evaluation and evidence-backed state transitions.

## Threat: model repeats a failed action

Control: bounded retries, failed-attempt history, proposal fingerprinting, and duplicate rejection.

## Threat: model requests excess access

Control: default-deny policy and narrow capability leases.

## Threat: approved payload changes before execution

Control: approval bound to the normalized proposal hash.

## Threat: stale result changes current state

Control: expected pre-state checks and state version validation.

## Threat: action executes twice

Control: idempotency keys and duplicate transition detection.

## Threat: audit history is altered

Control: append-only event storage verified against a separately owned same-VM checkpoint custodian, with pre-commit pledges and post-commit confirmation. Hash-chain consistency alone does not establish an unattested suffix's origin. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#integrity-and-trusted-heads) defines the selected scope and named failure dispositions. These controls remain planned.

## Threat: tool output contains secrets

Control: redaction before logging, projection, or user display.

## Threat: runtime reaches recovery authority

Control: distinct runtime/custodian identities, local peer authentication, a separately allowlisted operator endpoint, protected files/parents and actual denied-access verification. Runtime credentials cannot enroll an existing store, reset custody or change epochs. A producer role ID is not a replacement for OS authentication.

## Threat: crash resembles journal substitution

Control: durable PENDING before SQLite commit, COMMITTED before head publication, exact-request replay and checkpoint-confirmed read visibility. Only a stored event matching its prior pledge can resume confirmation automatically; a missing pledged event remains operator-only.

## Residual risk

The same-VM design trusts guest root, kernel, administrator and durable storage behavior. Whole-VM rollback or compromise of both custody domains is outside its detection claim. Same-process observation/evaluation cannot resist compromise of the trusted runtime. Production changes to these boundaries invalidate affected evidence and require review.

External systems may behave unpredictably. Compensation may not erase notifications, downstream actions, or historical effects. Warband must record these residual effects rather than claiming a perfect rollback.
