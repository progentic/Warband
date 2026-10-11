# Documentation Guidance

These instructions apply to work under `docs/`.

## Required behavior

- Preserve the authority order defined in `docs/governance/README.md`.
- Explain the user-visible protection before introducing technical vocabulary.
- Use `MUST`, `MUST NOT`, `SHOULD`, and `MAY` only when the statement is intended to be normative.
- Keep User, Engineering, Security, and Verification contracts consistent.
- Preserve existing `WB-*` identifiers. Add new identifiers instead of renumbering old ones.
- A material architecture change requires an ADR in `docs/decisions/`.
- Update `docs/verification/traceability-matrix.md` when a requirement, contract, implementation path, test path, or user behavior changes.
- ChatGPT project memory and saved responses are working context, not authoritative documentation.

## Writing standard

Use short, direct sentences. State what the rule protects, what it permits, what it blocks, and what happens on failure.

## Required check

Run `python3 scripts/check_docs.py` after documentation changes.
