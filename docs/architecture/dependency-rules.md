# Dependency Rules

These rules keep authority inside the trusted core.

## Domain

The domain package defines identifiers and immutable value types. It must not call models, tools, storage, or policy.

## Model adapters

Model adapters may create proposals. They must not import or call authoritative state-transition code.

## Tools

Tools may execute only through the gateway and a valid capability. They must not authorize themselves.

## Policy

Policy may inspect normalized proposals and runtime context. It must not execute tools or commit state.

## Evaluation

Evaluators may inspect observations and produce evaluation results. They must not approve execution or commit state.

## State

The state package owns authoritative transition rules. It must not call the model or fabricate evaluator evidence.

## Runtime coordinator

The coordinator connects the packages. It must not bypass their ownership boundaries.

## Phase 1 foundation dependencies

The CLI imports domain and fixture packages. Fixture imports domain vocabulary and the Odin endian library; decoding produces data, not verified facts. Domain validation has no I/O, model, tool, or storage dependency. No authoritative state writer exists in Phase 1.
