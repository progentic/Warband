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

## Current phase and remaining obligations

[ADR-0004](../decisions/0004-reproducible-odin-toolchain-and-ci.md) records foundation acceptance. [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md) records Phase 2 design acceptance; the [entry review](../engineering/phase2-entry-review.md) defines the authorized implementation scope and its pure-code follow-ons.

The [foundation obligations table](PHASE_PLAN.md#foundation-obligations-carried-to-production) tracks recorded Ubuntu rejection evidence, pending promotion, dependency recovery and structural finding closure at their named gates.

## Technical details

- [Phase 1 acceptance and evidence](../decisions/0004-reproducible-odin-toolchain-and-ci.md)
- [Remaining foundation work](phase1-closure-plan.md)
- [Linux runner compatibility](../decisions/0006-hosted-linux-runner-compatibility.md)
