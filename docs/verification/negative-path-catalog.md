# Negative-Path Catalog

These scenarios should be implemented before broad runtime features.

- **WB-NEG-001:** Malformed proposal is rejected.
- **WB-NEG-002:** Unknown tool is rejected.
- **WB-NEG-003:** Unauthorized target is rejected.
- **WB-NEG-004:** Expired capability is rejected.
- **WB-NEG-005:** Duplicate execution does not create another transition.
- **WB-NEG-006:** Stale result does not change current state.
- **WB-NEG-007:** Model success claim without evidence is ignored.
- **WB-NEG-008:** Approved payload mutation invalidates approval.
- **WB-NEG-009:** Tampered audit event breaks chain verification.
- **WB-NEG-010:** Missing recovery policy blocks a state-changing action.
- **WB-NEG-011:** Secret-bearing tool output is redacted.
- **WB-NEG-012:** Unknown schema version fails closed.

## Phase 1 foundation controls

WB-NEG-001 through WB-NEG-012 remain deferred runtime obligations. These additional controls verify tooling and fixture boundaries without claiming the earlier controls implemented.

- **WB-NEG-013:** Missing, malformed, unknown, duplicate-key, or boolean project phase fails governance validation.
- **WB-NEG-014:** Omitted/deleted test packages, unexpected names/counts, and unsuccessful compiler reports fail the test gate.
- **WB-NEG-015:** Truncated/oversized fixture bytes, unknown fixture schema, and empty identifiers fail decoding or domain validation.
- **WB-NEG-016:** Phase 1 cannot bypass required documents, contract headings, repository link bounds, guidance limits, skill metadata, or traceability.

Verification lives in `tests/governance/`, `tests/odin/negative/`, and the manifest runner. No capability, approval, persistence, worker, or audit acceptance exists in this phase.
