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

Keep orchestration, pure domain decisions, and technical operations separate under the existing High/Mid/Low hierarchy. High procedures call Mid procedures only. Mid procedures apply rules to supplied values, remain pure, and call only permitted Low helpers. Low procedures implement narrow technical operations without calling upward or making policy decisions. Entrypoints have no exempt fourth classification.

The fixture format is portable verification data, not an accepted event-store format. Ticks and identifiers are explicitly supplied; encoding reads no wall clock or random identity.

[ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) records the owner's Option A direction on 2026-10-11. The previous fourth-level entrypoint proposal is not selected. The [focused effect-composition review](phase1-effect-composition-review.md) maps the three existing entrypoints and records why their required I/O cannot currently compose with pure application decisions under all of the unchanged rules. The three findings remain open. Passing behavior tests do not establish a legal call graph, and the contradiction does not authorize an exception or additional framework.
