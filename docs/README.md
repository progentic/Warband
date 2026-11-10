# Help and documentation

Start with one of the three guides below. The subfolders group the Warband team's design, engineering, and project records by topic. The folder index follows the guides.

## Users

Start with the [user guide](users.md) to learn what Warband can do today, which commands to run, and what to expect. The guide also describes planned features in plain language.

## Maintainers

Use the [maintainer guide](maintainers.md) to update Warband, review changes, run the required checks, and prepare releases.

## Developers

Use the [developer guide](developers.md) to follow the code, understand how its parts fit together, and find the rules that govern implementation.

## Warband development team records

The repository is the authoritative record for Warband's design and project decisions. See the [authority order](governance/README.md#authority-order) for which documents take precedence. ChatGPT project instructions, project sources, memory, saved responses, and chats provide working context.

| Folder | What it contains |
| --- | --- |
| [Decisions](decisions/) | Design decisions and the reasons behind them. |
| [Governance](governance/) | Document authority, project guidance, and how the team records approvals. |
| [Foundation](foundation/) | Why Warband exists and the rules every implementation must follow. |
| [Architecture](architecture/) | How the system is divided and how data and authority move through it. |
| [Contracts](contracts/) | What users can rely on, what the code must do, which security boundaries apply, and how the team verifies them. These four views must agree. |
| [Engineering](engineering/) | How contributors structure, write, test, and review code. |
| [Security](security/) | What Warband protects, the threats it faces, and the controls and remaining risks. |
| [Verification](verification/) | Verification plans, evidence, and traceability from requirements to checks. |
| [Reference](reference/) | Shared terms and stable identifiers. |

### Requirement words

- **MUST** means the requirement is mandatory.
- **MUST NOT** means the behavior is prohibited.
- **SHOULD** means the rule is expected unless a documented reason justifies an exception.
- **SHOULD NOT** means the behavior is normally avoided.
- **MAY** means the behavior is optional.
- **INVARIANT** means a condition that must remain true in every valid system state.
