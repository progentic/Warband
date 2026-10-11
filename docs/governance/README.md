# Governance

This folder explains how Warband keeps project instructions, repository documents, ChatGPT project context, and Codex guidance aligned.

## Source of truth

The Git repository is the authoritative record.

ChatGPT project instructions, uploaded project sources, project memory, saved responses, and chat history provide working context. They do not replace accepted repository documents.

A decision becomes authoritative only after it is written in the correct repository document, reviewed, and committed.

## Authority order

When documents disagree, use this order:

1. `docs/foundation/runtime-constitution.md`
2. Architecture contracts under `docs/contracts/`
3. Accepted decisions under `docs/decisions/`
4. Engineering and security standards
5. User and operational guidance
6. Examples, chat summaries, and saved project responses

## OpenAI guidance layers

Warband uses separate layers for separate jobs:

- ChatGPT Project instructions define how ChatGPT should work inside the project.
- Project sources provide reference documents and shared context.
- `AGENTS.md` gives Codex durable repository guidance.
- Nested `AGENTS.md` files add rules for a specific directory.
- Repo-scoped skills under `.agents/skills/` package repeatable review workflows.
- CI and tests enforce rules that instructions alone cannot guarantee.

Instructions guide behavior. Repository controls and verification enforce behavior.

## Phase 1 closure

The [closure plan](phase1-closure-plan.md) records source publication, hosted evidence retention, dependency recovery, ownership and required-check gates. The repository is selected and the hosted baseline passes; ownership and formal acceptance remain pending. [ADR-0006](../decisions/0006-hosted-linux-runner-compatibility.md) tracks the announced runner migration without relaxing the toolchain guard. Technical verification does not imply formal ADR acceptance or Phase 2 authorization.
