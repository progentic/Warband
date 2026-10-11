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

## Phase 1 applicability

No proposal interface or execution gateway exists yet. Fixture schema/length tests exercise foundation data only. They do not satisfy proposal rejection or audit-event obligations.
