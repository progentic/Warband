# ADR-0010: Isolate provider access from marker execution

## Status

Accepted by Proto (Ian) for the Phase 4 entry design on protected merge of the [entry review](../engineering/phase4-entry-review.md). Runtime activation requires separate authorization.

## Context

The model needs a way to suggest a marker action. Giving the Phase 3 worker network access would expose its execution environment to provider traffic. Giving the adapter approval or evidence-producing authority would allow a provider response to influence the decision about its own proposal.

## Decision

Use one isolated adapter with a dedicated credential and a single approved destination. Give the provider a public or synthetic catalog example and an opaque request ID. Its reply enters the same local validator used by deterministic fixtures. The [model proposal contract](../contracts/model-proposals.md#phase-4-boundary-specification) defines the provider profile, wire format, data controls, limits and failure behavior.

## Security and compatibility

The runtime binds a valid candidate to the operator's intent and supplies the authority-bearing fields. The authenticated local CLI approves the exact normalized marker proposal. Phase 3 supplies the network-denied worker, registered observer, independent evaluator and evidence-backed acceptance. Its event format and replay rules apply to the resulting marker history. [ADR-0009](0009-controlled-local-marker-execution.md)

## Verification

The [Phase 4 traceability rows](../verification/traceability-matrix.md#phase-4-provider-and-operator-workflow) identify the live and fixture checks owed before exit.
