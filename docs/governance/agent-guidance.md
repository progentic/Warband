# Agent Guidance Policy

This document explains how Warband uses `AGENTS.md` and repo-scoped skills.

## Root guidance

The root `AGENTS.md` contains only rules that apply to every repository task. It routes the agent to authoritative documents and names the required validation command.

It must not become a second copy of the runtime constitution or engineering manual.

## Nested guidance

Use a nested `AGENTS.md` when a directory has stable rules that do not apply to the entire repository.

Examples for later phases:

- `src/state/AGENTS.md` for state-transition review rules;
- `src/security/AGENTS.md` for cryptographic and secret-handling rules;
- `tests/AGENTS.md` for invariant and negative-path expectations.

Use `AGENTS.override.md` only when the local directory must replace, rather than extend, broader guidance. Do not use it as a routine instruction file.

## Skills

Use a repo-scoped skill for a repeatable workflow that is too detailed for `AGENTS.md`.

The initial `warband-governance-review` skill reviews a proposed change against the constitution, contracts, security rules, and traceability requirements.

## Enforcement rule

Agent guidance does not prove compliance. CI, type rules, package boundaries, and tests must enforce every critical guarantee.
