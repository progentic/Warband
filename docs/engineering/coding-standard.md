# Coding Standard

## Explicit decisions

Security decisions must use named enums or decision types, not bare booleans.

Prefer:

`permit`, `reject`, `require_approval`

Avoid:

`allowed: bool`

## Typed identifiers

Task, run, proposal, event, fact, evidence, and capability identifiers must use distinct types.

## No hidden mutation

Security-sensitive state changes must not occur inside getters, serializers, log functions, constructors, or cleanup code.

## Explicit errors

Fallible operations must return typed errors with stable codes. Errors shown to users must not expose secrets, capability tokens, raw prompts, or restricted data.

## Controlled time and identity

Code that depends on time, random identifiers, or replay behavior should receive those services explicitly so tests can control them.

## Boundary rule

Raw model output must not cross the proposal-normalization boundary. Raw tool output must not become evidence until an evaluator processes it.

## Default safety

Unknown enum values, tools, policy rules, schema versions, and effect kinds must fail closed.

## Phase 1 procedure structure

Keep orchestration, pure domain decisions, and technical operations separate. Pure domain rules receive values and return typed outcomes. CLI and build/verification entry points are effectful boundary adapters; they are not claimed to be pure domain functions. Filesystem traversal, parsing, compiler calls, architecture inspection, and presentation belong at technical boundaries.

The fixture format is portable verification data, not an accepted event-store format. Ticks and identifiers are explicitly supplied; encoding reads no wall clock or random identity.

The supplied structural guidance's literal call graph conflicts with its purity rule when Mid functions call I/O wrappers. Effect dispatch and general procedure layering remain unresolved, as ADR-0004 specifies. This foundation does not silently accept a general runtime layering exception. Domain validation remains free of I/O; package layout is not a sandbox guarantee.

### Proposed narrow entrypoint clarification

**Approval pending.** [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) records this proposal. It is not an operative exception until the user explicitly approves it; passing tests do not close the hierarchy findings.

> Entrypoints are boundary adapters, not High level domain procedures. They may acquire external inputs, invoke application procedures, and present results. They must not contain policy decisions, evidence evaluation, authoritative state transitions, or unrelated technical operations. Pure domain procedures remain isolated from filesystem, process, network, and database operations.

The proposed Phase 1 scope is the Odin CLI entrypoint and the documentation/build-manifest entrypoints. Input acquisition and presentation stay at their technical boundaries. Runtime authorization, evidence evaluation and authoritative transitions retain the stronger High/Mid/Low contracts. This proposal does not make a runtime coordinator an entrypoint or permit domain rules to call I/O wrappers.
