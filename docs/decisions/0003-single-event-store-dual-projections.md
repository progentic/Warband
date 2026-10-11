# ADR-0003: One event store with two projections

## Status

Accepted

## Context

Separate physical ledgers for audit history and authoritative state would create synchronization risk.

## Decision

Warband will use one append-only event store and derive:

- an audit projection containing all events;
- an authoritative projection containing only accepted state-changing facts.

## Security consequences

The design preserves full history while keeping authoritative state strict and reproducible.

## Verification

Tests will confirm that both projections are derived from the same event sequence and that rejected events never enter the authoritative projection.
