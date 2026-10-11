# Authoritative State Contract

## Purpose

Prevent model claims, tool output, or stale results from directly changing system truth.

## User contract

Warband marks work complete only after it has checked the result.

## Engineering contract

Only the state-transition boundary may commit authoritative facts. The transition requires a valid policy decision, accepted evidence, the expected current state, and a transition that has not already been committed.

## Security contract

Model output, tool output, and evaluator output are all inputs. None may directly mutate authoritative state.

## Verification contract

Tests must prove that Warband rejects:

- direct fact insertion;
- unverified completion;
- stale transitions;
- duplicate transitions;
- mismatched task and run identifiers;
- evaluator results without valid evidence.

## Failure behavior

When a transition cannot be proven safe, Warband must leave authoritative state unchanged and record the rejection.
