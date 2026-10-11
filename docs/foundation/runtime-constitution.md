# Runtime Constitution

This is the highest-authority technical document in the repository.

Every Warband implementation MUST obey these rules.

## WB-CON-001: Runtime authority

The runtime is the only authority allowed to commit changes to authoritative state.

## WB-CON-002: Proposal isolation

Model output is untrusted input. A proposal has no direct execution or state-mutation authority.

## WB-CON-003: Independent verification

A model claim MUST NOT be used as proof that the model's own proposal succeeded.

## WB-CON-004: Policy before execution

Every executable proposal MUST receive an explicit policy decision before execution.

## WB-CON-005: Least privilege

Every execution MUST receive a capability limited by scope, action, target, and time.

## WB-CON-006: Evidence-backed transitions

Every authoritative transition MUST reference recorded evidence and the event that produced it.

## WB-CON-007: Audit completeness

Every security-relevant proposal, decision, execution, evaluation, approval, and transition MUST produce an audit event.

## WB-CON-008: Replay safety

Duplicate, stale, or out-of-order results MUST NOT produce duplicate or invalid state changes.

## WB-CON-009: Recovery planning

Every state-changing action MUST have a defined recovery, compensation, approval, or rejection policy before execution.

## WB-CON-010: Model independence

Runtime safety MUST NOT depend on a specific model provider behaving correctly.

## Operational rule

> No model output directly changes authoritative state. Only an authorized runtime transition supported by recorded evidence may do so.
