---
name: warband-governance-review
description: Review Warband architecture, governance, documentation, or implementation changes for conflicts with the runtime constitution, architecture contracts, security rules, negative paths, and traceability. Use for design changes, feature plans, pull request reviews, or governance updates. Do not use for spelling-only edits that do not change meaning.
---

# Warband Governance Review

Review the requested change in this order:

1. Read `AGENTS.md` and the nearest nested `AGENTS.md`.
2. Read `docs/foundation/runtime-constitution.md`.
3. Identify every affected `WB-CON-*` and `WB-INV-*` identifier.
4. Read the related contract, security document, and accepted ADRs.
5. Check whether the User, Engineering, Security, and Verification descriptions still agree.
6. Check the negative-path catalog for missing failure cases.
7. Check the traceability matrix for missing or stale mappings.
8. Reject claims of safety that rely only on prompts, model behavior, package layout, or human intent.
9. Separate blocking violations from recommended improvements.

Return:

- **Verdict:** aligned, conditionally aligned, or not aligned.
- **Blocking findings:** contradictions or missing controls that must be fixed.
- **Required document updates:** exact file paths and identifiers.
- **Required verification:** tests or checks needed to prove the change.
- **Non-goals:** work that should not be added to the current task.
