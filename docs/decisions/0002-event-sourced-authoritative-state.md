# ADR-0002: Authoritative state is derived from verified facts

## Status

Accepted

## Context

The runtime needs a complete history without allowing unverified claims to become system truth.

## Decision

Warband will record an append-only event history. The authoritative state will be rebuilt only from verified, policy-authorized facts that are eligible to change state.

## Security consequences

Model claims and failed attempts remain visible for audit but cannot alter authoritative state.

## Verification

Replay tests will rebuild authoritative state from accepted facts and confirm that unverified events do not affect the result.
