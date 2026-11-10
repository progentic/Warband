# Warband Repository Guidance

## Mission

Warband is a policy-controlled execution runtime. Treat every model output as untrusted input. Preserve this rule:

> No model output directly changes authoritative state. Only an authorized runtime transition supported by recorded evidence may do so.

## Read before changing the repository

1. `docs/foundation/runtime-constitution.md`
2. `docs/architecture/README.md`
3. The contract and security documents related to the requested change
4. `docs/engineering/definition-of-done.md`
5. `docs/verification/traceability-matrix.md`

## Current phase

`project.json` declares the phase. Phase 1 foundation implementation is accepted by Ian in `docs/decisions/0004-reproducible-odin-toolchain-and-ci.md`; its listed release debts and hosted Check B remain open. The original implementation scope is in `docs/engineering/phase1-agent-execution-directive.md`. Do not add Phase 2 execution, providers, capabilities, persistence, or deployment services under this authorization. Do not configure remotes, commit or publish without separate authorization.

## Working rules

- Keep the runtime constitution, contracts, security rules, and verification plan aligned.
- Do not renumber stable `WB-*` identifiers.
- Do not treat chat history, project memory, model claims, or saved responses as authoritative design decisions.
- Record material design changes in `docs/decisions/`.
- Use plain language first. Name the technical mechanism after explaining what it protects or prevents.
- Keep `AGENTS.md` concise. Put detailed rules in the nearest authoritative document.
- Do not commit `AGENTS.override.md` unless a task explicitly requires a scoped replacement.

## Required check

Run:

```sh
python3 scripts/check_docs.py
```

## Code review rules

Flag any change that:

- weakens proposal isolation, policy-before-execution, independent verification, least privilege, audit completeness, or replay safety;
- changes an accepted rule without updating its contract, decision record, negative paths, and traceability row;
- duplicates governance text in a way that can drift;
- claims a guarantee that has no verification method.
