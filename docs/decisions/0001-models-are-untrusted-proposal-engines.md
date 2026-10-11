# ADR-0001: Models are untrusted proposal engines

## Status

Accepted

## Context

Language models are useful for interpretation and planning but cannot be trusted to maintain authoritative state, enforce policy, or prove their own success.

## Decision

Warband will treat every model as an interchangeable, untrusted proposal engine.

Models may return typed proposals. They may not execute tools, issue capabilities, approve actions, or commit state.

## Security consequences

This removes model behavior from the trusted authority boundary.

## Verification

Invariant tests will attempt direct state mutation and direct execution from the model adapter and confirm that both are rejected.
