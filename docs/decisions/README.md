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

## Current proposed work

- [ADR-0004](0004-reproducible-odin-toolchain-and-ci.md) covers the locally verified toolchain and still requires ownership, review and formal acceptance.
- [ADR-0005](0005-event-integrity-acceptance-and-recovery.md) proposes the event, evidence, acceptance and recovery boundary. It is design-only and does not authorize Phase 2 code.
