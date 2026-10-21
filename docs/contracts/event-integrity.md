# Event Integrity Contract

## Purpose

Provide a reliable history of what Warband proposed, allowed, executed, observed, and accepted.

## User contract

Warband keeps a clear activity history so the user can see what happened and why.

## Engineering contract

Security-relevant events are appended in order. Each record includes stable identifiers, a timestamp, a parent hash, and an event hash calculated from canonical data. The Phase 2 candidate in [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#amendment-resolved-phase-2-decision-candidate) specifies full store/epoch/sequence references, versioned bytes and per-event prepare/commit/confirm. Acknowledgment, dispatch and authoritative publication wait for durable custody confirmation. The event store and custody history are distinct: custody contains integrity metadata, not another authoritative ledger.

## Security contract

A changed, removed, or reordered event must be detectable during audit verification against the independently trusted checkpoint covering that event. Under the selected same-VM custody model, this assumes the attacker can rewrite the journal but cannot control the custodian identity/storage, VM kernel or administrator. Whole-VM rollback and control of both custody domains are outside that detection claim. A self-consistent unattested suffix is not trusted evidence.

## Verification contract

Tests must prove that event alteration, broken parent links, duplicate full event identities, invalid ordering, anchored truncation and conflicting heads are detected within the stated threat model. They must also distinguish an exact pledged tail from an unpledged suffix and verify actual runtime-identity write denial to custody files/operator operations. These are future Phase 2 proofs, not foundation test results.

## Failure behavior

A failed audit-chain check must block replay-based trust and trigger an integrity warning. Preserve evidence and use ADR-0005's named fault/recovery disposition. A missing pledged event requires operator reconciliation; no automatic cancellation or chain-only re-attestation is permitted. While storage is unavailable, report failure without falsely claiming that a fault event was durably recorded.
