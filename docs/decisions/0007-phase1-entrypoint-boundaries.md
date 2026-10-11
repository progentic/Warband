# ADR-0007: Phase 1 entrypoint boundaries

- **Status:** Proposed
- **Date:** 2026-10-10
- **Decision owner:** Unassigned
- **Rule approval:** Pending explicit user approval
- **Scope:** Three existing Phase 1 entrypoints; no Phase 2 implementation
- **Supersedes:** None
- **Related:** ADR-0004, still Proposed

## Problem

The supplied procedure hierarchy does not distinguish an executable entrypoint from a pure domain workflow. High functions call only Mid functions; Mid functions are pure; Low functions cannot call upward. Without a scoped boundary rule, an executable cannot acquire external inputs, invoke pure decisions and present results through a legal call graph.

The existing Phase 1 code has three recorded findings. Passing builds do not approve a hierarchy exception or establish runtime security properties.

## Proposed clarification

The proposed wording is recorded once in [the engineering standard](../engineering/coding-standard.md#proposed-narrow-entrypoint-clarification). This record explains the scope and verification rather than duplicating that rule. Explicit approval is required before closing the findings. Neither this proposal nor its implementation tests accept ADR-0004 or authorize Phase 2.

## Candidate implementation

- Odin `main()` acquires arguments through `read_arguments`, passes them explicitly to the pure `parse_command`, then presents the selected CLI result. Parsing reads no process-global arguments or I/O. Existing command names, output bytes/streams and exit codes remain unchanged.
- `check_docs.main()` retains its existing inventory/validation/reporting composition. No forwarding function is introduced merely to rename the same operations. It qualifies only if the proposed boundary rule is approved.
- `build_manifest.main()` validates the requested platform, inspects artifact metadata, applies pure format/machine checks, acquires the remaining build observations, constructs the manifest through pure rules, then publishes it through technical output helpers. Architecture checks still precede linkage inspection. Inspection is in `manifest_io.py`; frozen observations and pure validation/construction are in `manifest_rules.py`.

The typed observations are build metadata, not accepted runtime evidence. The pure manifest procedure performs no file, subprocess or environment access. Unsupported platforms, wrong formats/machines and missing hosted runner identity still reject. Local runs do not inherit stale hosted image labels. Manifest field names and values remain compatible with the existing schema.

## Required verification

Retain the existing phase/document negative controls, exact Odin package inventory, five portable fixture tests, and real CLI smoke checks. Compare the old and new manifest output on the same executable and environment. Verify wrong formats/machines and missing hosted image/version rejection, including that a real rejected invocation does not overwrite the prior manifest.

Run clean source-only Python controls and independent Linux x64/macOS ARM64 hosted jobs. Inspect their artifact identities, reports and failure logs. Human review must also confirm that the split has not moved policy into acquisition or output helpers; tests alone cannot approve the boundary classification.

## Approval and disposition

Candidate code may be reviewed and tested on a draft branch. The three hierarchy findings remain open until the scoped rule is explicitly approved and the candidate implementation is reviewed. Do not mark this record or ADR-0004 Accepted from a build result. Maintainer ownership, formal governance, dependency recovery and ADR-0006 compatibility review remain separate gates.
