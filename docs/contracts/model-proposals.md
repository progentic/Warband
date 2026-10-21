# Model Proposal Contract

## Purpose

Allow language models to suggest actions without granting them authority.

## User contract

The AI may suggest a solution, but Warband checks the suggestion before anything happens.

## Engineering contract

The model must return a typed proposal that contains a known tool, validated arguments, an expected effect, a schema version, and stable identifiers.

## Security contract

Raw model output is untrusted. It must be parsed, normalized, validated, fingerprinted, and checked by policy before execution.

## Verification contract

Tests must prove that malformed, unknown, oversized, stale, duplicate, or unauthorized proposals are rejected.

## Failure behavior

Invalid proposals produce a safe error and an audit event. They do not execute.

## Phase applicability

No proposal interface or execution gateway is implemented yet. Fixture schema/length tests exercise foundation data only. They do not satisfy proposal rejection or audit-event obligations.

The Phase 2 design candidate accepts only the exact NoOp shape and fingerprint domain specified in [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#2-canonical-binary-v1). It binds task/run, expected task version, policy version, criterion, recovery and approval requirement. Unknown actions, altered bindings or approval-required input fail closed. Phase 2 provides rejection evidence for unsupported approval, not the positive operator approval path required in Phase 3. No provider or real tool is introduced by the design.
