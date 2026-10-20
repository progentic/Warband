# Event and Fact Model

An event records that something happened.

A fact records a verified condition that the runtime accepts as true.

Examples:

- `proposal_submitted` is an event.
- `policy_rejected` is a verified decision fact.
- `execution_failed` is a verified observation fact.
- `model_claimed_success` is only an event.
- `verification_passed` is a verified fact.
- `task_completed` is an authoritative state transition.

## Rule

All events are retained for audit. Only eligible verified facts may update authoritative state.

## Integrity

Events must be recorded in a stable order and linked through tamper-evident hashes. The event hash must be computed by Warband from a canonical representation. It must never be accepted from the model.

## Phase 2 identity and format candidate

The [ADR-0005 v1 registry](../decisions/0005-event-integrity-acceptance-and-recovery.md#2-canonical-binary-v1) defines `(store, epoch, sequence)` identity and exact payload/hash domains. Existing names above are conceptual examples; numeric v1 kinds and their schemas are defined only in that registry. Custody PENDING/COMMITTED/GENESIS/EPOCH frames attest event history; they are integrity metadata, not task facts or a second authoritative ledger. Unknown schema/kind/producer fails closed. No bytes are silently migrated or reinterpreted.
