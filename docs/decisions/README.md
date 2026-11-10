# Architecture Decision Records

This folder records decisions that are difficult to reverse or that affect trust, authority, compatibility, or security.

Create a new record when changing:

- authoritative state;
- event or fact structure;
- policy semantics;
- capability rules;
- approval binding;
- evaluator independence;
- audit integrity;
- serialization;
- recovery behavior;
- package dependency direction.

Do not rewrite accepted history. Add a new record that supersedes the old decision.

## Accepted Phase 1 decisions

- [ADR-0004](0004-reproducible-odin-toolchain-and-ci.md): Phase 1 build foundation, accepted 2026-11-10.
- [ADR-0007](0007-phase1-entrypoint-boundaries.md): Phase 1 program structure, accepted 2026-10-12.

## Current proposed work

- [ADR-0005](0005-event-integrity-acceptance-and-recovery.md): Event and recovery design. Phase 2 implementation is not authorized.
- [ADR-0006](0006-hosted-linux-runner-compatibility.md): Linux runner compatibility.

The linked records contain the technical details, evidence and remaining work.
