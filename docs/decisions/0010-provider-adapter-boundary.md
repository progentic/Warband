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

## Package 3a projection and envelope profile

The [approved increment 3 scope](../engineering/phase4-increment3-scope.md) assigns the fixed request to the credential-bearing transport and destination enforcement to the external connection policy. Package 3a defines the bytes at that boundary. The operation accepts the issued lowercase hex ID, catalog revision and identity. Revision 1 supplies the canonical example bytes. The deadline and cancellation signal belong to the local transport handoff.

The builder selects the pinned model and emits a single non-streaming, unstored completion with a strict JSON schema for the five marker proposal fields. The tool list is omitted. The developer message requests a schema-conforming proposal with the ID and Base64 payload echoed exactly. The user message consists of `request_id=<issued ID> payload_b64=<canonical Base64>`. Caller-supplied text, prior replies and provider metadata have no input field in the builder. With test ID `0123456789abcdef0123456789abcdef`, the empty and `abc` examples serialize to 786 and 790 bytes respectively. The fixtures compare hashes of the complete requests against independent JSON serialization.

The extractor requires `object=chat.completion`, the pinned model, one index-zero choice, `finish_reason=stop`, an assistant role and one content string. Length truncation, refusal/content filtering, tool calls, an unexpected finish reason and model mismatch have distinct dispositions. Malformed or conflicting fields yield an invalid-envelope result. Discarded metadata must also be well-formed JSON. Check duplicate decoded keys at the root, choice and message levels. Limit nested JSON containers to 64 levels and require paired Unicode surrogate escapes. The 64 KiB wire-body and 8,192-byte decoded candidate limits count bytes. The extractor removes one envelope string-escaping layer and passes the result unchanged to the increment 1 validator. Its typed candidate rejection survives that handoff.

Named model-package tests cover both catalog examples, closed projections, strict envelope failures, candidate parity and size boundaries. Testing transfer callbacks, endpoint request count, isolation and redaction across process boundaries belongs to packages 3b–3d. A live provider run still requires the recorded activation gates.
