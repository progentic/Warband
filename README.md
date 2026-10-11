# Warband

Warband is a policy-controlled execution runtime that uses language models as untrusted proposal engines.

The model may suggest what should happen. Warband decides what is allowed, performs the action inside a controlled boundary, checks the result, and records what actually happened.

This repository is implementing the locally authorized Phase 1 foundation. It contains a small CLI, deterministic fixtures, phase-aware governance, pinned compiler inputs, and GitHub Actions workflows. ADR-0004 remains Proposed with an unassigned owner. Formal approval is outstanding; Phase 2 authority and execution are not implemented.

## Start here

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

## Repository status

**Phase 1: Foundation verified locally and on hosted runners; formal acceptance pending**

`project.json` declares Phase 1. The CLI supports `version` and `fixture`; it cannot execute tools or commit authoritative state. See [Phase 1 build and verification](docs/engineering/phase1-build-and-verification.md) and [verification evidence](docs/verification/phase1-evidence.md).

The Phase 1 foundation is published on the selected [progentic/Warband repository](https://github.com/progentic/Warband), preserving its existing `main` history. See [publication and runner evidence](docs/verification/phase1-publication-evidence.md) for observed results and pending checks. The active [LICENSE](LICENSE) matches the remote BSD 3-Clause license. The original bootstrap is retained unchanged locally. The [closure plan](docs/governance/phase1-closure-plan.md) records the remaining gates. No provider, persistence, service deployment, or UI is included.
