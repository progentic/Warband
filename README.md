# Warband

Warband is a policy-controlled execution runtime that uses language models as untrusted proposal engines.

The model may suggest what should happen. Warband decides what is allowed, performs the action inside a controlled boundary, checks the result, and records what actually happened.

## Start here

- [Changelog](CHANGELOG.md)
- [Project charter](docs/foundation/project-charter.md)
- [Runtime constitution](docs/foundation/runtime-constitution.md)
- [System architecture](docs/architecture/README.md)
- [Governance](docs/governance/README.md)
- [Engineering standards](docs/engineering/README.md)
- [Security model](docs/security/security-model.md)
- [Verification plan](docs/verification/README.md)

## AI project guidance

- `AGENTS.md` gives Codex durable repository guidance.
- `docs/AGENTS.md` adds documentation-specific guidance.
- `docs/governance/chatgpt-project-instructions.md` contains the instructions to copy into ChatGPT Project settings.
- `docs/governance/project-source-manifest.md` lists the core files to add as ChatGPT project sources.
- `.agents/skills/warband-governance-review/` contains the repo-scoped governance review skill.

## Core rule

> No model output directly changes authoritative state. Only an authorized runtime transition supported by recorded evidence may do so.

## Validate the baseline

```sh
python3 scripts/check_docs.py
```
