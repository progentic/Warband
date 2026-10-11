# Documentation Guide

This folder is the main source of truth for Warband's design.

The documents are grouped by purpose:

- `foundation/` explains why Warband exists and the rules every implementation must obey.
- `architecture/` explains how the system is divided and how data and authority move through it.
- `contracts/` translates each important feature into user, engineering, security, and verification terms.
- `engineering/` defines how contributors should structure, write, test, and review code.
- `security/` explains the assets, threats, boundaries, controls, and remaining risks.
- `governance/` explains document authority, ChatGPT Project setup, `AGENTS.md`, project sources, and agent skills.
- `decisions/` records important design choices and why they were made.
- `verification/` explains how the repository proves that the architecture is still being followed.
- `reference/` provides shared terms and stable identifiers.

## Normative words

- **MUST** means the requirement is mandatory.
- **MUST NOT** means the behavior is prohibited.
- **SHOULD** means the rule is expected unless a documented reason justifies an exception.
- **SHOULD NOT** means the behavior is normally avoided.
- **MAY** means the behavior is optional.
- **INVARIANT** means a condition that must remain true in every valid system state.

## Documentation rule

The same system behavior must be explainable in four aligned ways:

1. User contract: what the person can rely on.
2. Engineering contract: what the implementation must do.
3. Security contract: what boundary is enforced.
4. Verification contract: how the repository proves the rule.

## AI context rule

The repository is authoritative. ChatGPT project instructions, project sources, memory, saved responses, and chats help agents work with the repository, but they do not replace accepted documents.
