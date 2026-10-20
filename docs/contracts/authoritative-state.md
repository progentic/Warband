# Authoritative State Contract

## Purpose

Prevent model claims, tool output, or stale results from directly changing system truth.

## User contract

Warband marks work complete only after it has checked the result.

## Engineering contract

Only the state-transition boundary may commit authoritative facts. The transition requires a valid policy decision, accepted evidence, the expected current state, and a transition that has not already been committed. The Phase 2 [ADR-0005 transition table](../decisions/0005-event-integrity-acceptance-and-recovery.md#4-versions-and-acceptance-table) separates task version, control revision and attempt identity. Expected versions, evidence/reference closure and scoped uniqueness are checked in the same SQLite transaction as event/index insertion. Indexes are reconstructible from the one event history. A committed-but-unconfirmed event cannot be presented as authoritative completion.

## Security contract

Model output, tool output, and evaluator output are all inputs. None may directly mutate authoritative state.

## Verification contract

Tests must prove that Warband rejects:

- direct fact insertion;
- unverified completion;
- stale transitions;
- duplicate transitions;
- mismatched task and run identifiers;
- evaluator results without valid evidence;
- cross-store/epoch event references, consumed/revoked capability misuse and competing acceptance of the same attempt.

Replay validates custody coverage and the recorded transition/evidence chain, then applies pure rules without a live clock, model, tool or current-policy reinterpretation. Phase 2 inline control evidence and independently evaluated completion evidence have the distinct schemas in ADR-0005; no caller-supplied verification flag substitutes for either.

## Failure behavior

When a transition cannot be proven safe, Warband must leave authoritative state unchanged and record the rejection when durable storage is available. An uncertain local commit is reconciled, not described as a rollback. Rejection-recording failure stops progress and is surfaced explicitly; it does not fabricate a durable audit receipt.
