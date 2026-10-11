# Contributing

Warband treats documentation as part of the system design, not as an afterthought.

Before proposing a change:

1. Read `AGENTS.md`.
2. Read the [runtime constitution](docs/foundation/runtime-constitution.md).
3. Check whether the change affects an existing architecture contract or decision.
4. Update the related user expectation, engineering rule, security guarantee, and verification method.
5. Run `python3 scripts/check_docs.py`.

A change is not complete when only one document is updated. The Constitution, contracts, security rules, decisions, negative paths, and traceability must remain aligned.

Runtime code must not be added during the documentation-baseline phase unless the task explicitly starts an implementation phase.
