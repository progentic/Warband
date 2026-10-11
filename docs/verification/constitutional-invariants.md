# Constitutional Invariants

These identifiers are stable. Do not renumber them after implementation begins.

- **WB-INV-001:** Model output cannot directly mutate authoritative state.
- **WB-INV-002:** Every executable proposal passes schema and policy validation.
- **WB-INV-003:** Every execution uses an explicit, bounded capability.
- **WB-INV-004:** Every state-changing action has a recovery, approval, or rejection policy.
- **WB-INV-005:** Completion requires independent verification.
- **WB-INV-006:** Every security-relevant decision produces an audit event.
- **WB-INV-007:** Human approval is bound to the exact normalized proposal.
- **WB-INV-008:** Duplicate or stale execution cannot produce another state transition.
- **WB-INV-009:** Unverified events cannot enter the authoritative projection.
- **WB-INV-010:** A learned pattern cannot be promoted without recorded verification evidence.
