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

Control: append-only storage and chained hashes.

## Threat: tool output contains secrets

Control: redaction before logging, projection, or user display.

## Residual risk

External systems may behave unpredictably. Compensation may not erase notifications, downstream actions, or historical effects. Warband must record these residual effects rather than claiming a perfect rollback.
