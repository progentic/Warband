# Event Integrity Contract

## Purpose

Provide a reliable history of what Warband proposed, allowed, executed, observed, and accepted.

## User contract

Warband keeps a clear activity history so the user can see what happened and why.

## Engineering contract

Security-relevant events are appended in order. Each record includes stable identifiers, a timestamp, a parent hash, and an event hash calculated from canonical data.

## Security contract

A changed, removed, or reordered event must be detectable during audit verification.

## Verification contract

Tests must prove that event alteration, broken parent links, duplicate identifiers, and invalid ordering are detected.

## Failure behavior

A failed audit-chain check must block replay-based trust and trigger an integrity warning.
