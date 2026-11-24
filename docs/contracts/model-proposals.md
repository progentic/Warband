# Model Proposal Contract

## Purpose

Allow language models to suggest actions without granting them authority.

## User contract

The AI may suggest a solution, but Warband checks the suggestion before anything happens.

## Engineering contract

The model must return a typed proposal that contains a known tool, validated arguments, an expected effect, a schema version, and stable identifiers.

## Security contract

Raw model output is untrusted. It must be parsed, normalized, validated, fingerprinted, and checked by policy before execution.

Only the issuing execution can use a live grant. Check its private grant entry and a fresh elapsed-time observation at claim confirmation and again immediately before dispatch. Both checks must fall strictly before expiry. After restart, durable authorization and claim evidence alone cannot permit dispatch. [Live capability clock ruling](../decisions/0005-event-integrity-acceptance-and-recovery.md#accepted-live-capability-clock-amendment)

## Verification contract

Tests must prove that malformed, unknown, oversized, stale, duplicate, or unauthorized proposals are rejected.

## Failure behavior

Invalid proposals produce a safe error and an audit event. They do not execute.

## Phase 4 boundary specification

Phase 4 entry (owner: Proto, 2026-11-24) binds this contract to one provider profile and one action. [Phase 4 entry review](../engineering/phase4-entry-review.md)

**Projection.** The adapter may send only a fixed instruction, the proposal schema below, an opaque single-use request ID, and an operator-selected intent from a reviewed catalog of public or synthetic marker examples. Free-form operator text, task history, runtime identifiers, paths, tool output, and credentials are outside the projection. Unclassified fields are rejected before egress. Raw provider requests and replies are held in memory for the call only; the normalized proposal and authority evidence are retained under existing custody rules. Each request sets `store: false`. Before activating the adapter, the owner verifies that voluntary input/output sharing is disabled for the dedicated API project. The owner accepts the provider's documented abuse-monitoring retention for this projection, including its stated exceptions. The dedicated project credential is readable only by the isolated adapter identity. [Provider sharing controls](https://help.openai.com/en/articles/10306912-sharing-feedback-evaluation-and-fine-tuning-data-and-api-inputs-and-outputs-with-openai) · [Provider retention terms](https://developers.openai.com/api/docs/guides/your-data)

**Provider profile.** OpenAI Chat Completions, pinned snapshot `gpt-5.4-mini-2026-03-17`, one non-streaming completion, tools disabled. A snapshot change requires profile review; an unavailable snapshot yields a failure. The adapter's single provider-independent operation submits the approved projection and returns bounded, untrusted candidate bytes or a typed failure. Live and fixture responses enter the same local parser.

**Proposal shape.** The candidate bytes must be exactly one UTF-8 JSON object of at most 8,192 bytes before parsing, with exactly five required fields and no duplicate or unknown keys:

- `schema_version`: integer equal to 1.
- `request_id`: the issued 32-character lowercase hex ID, echoed exactly.
- `action`: `create_marker`.
- `expected_effect`: `marker_contains_payload`.
- `payload_b64`: canonical padded RFC 4648 Base64 decoding to 0–4,096 bytes.

The decoded bytes must match the selected public or synthetic example. Wrong types, trailing content, stale IDs, and repeat delivery are rejected before intake. Each request ID is bound locally to one operator intent and consumed at most once, including across restart. The runtime supplies every authority-bearing field and computes the existing Phase 3 proposal fingerprint from the normalized proposal. The adapter has no registered authority role, and provider text claiming approval or success has no effect on approval, observation, evaluation, or acceptance.

**Egress.** Only HTTPS `POST` to `api.openai.com:443/v1/chat/completions`, TLS 1.2 or later, certificate and hostname verification on. Destination restrictions are enforced outside the adapter process with a trusted resolver; private, loopback, link-local, and reserved destination addresses are denied. Redirects, proxy overrides, and caller-supplied URLs or headers are disabled. The credential is sent only as the bearer token for that endpoint. The serialized request body is at most 16 KiB, response headers at most 16 KiB, and the uncompressed response body at most 64 KiB; compressed responses are declined. Five seconds to connect, 30 seconds total from request start, one attempt. Cancellation, timeout, rate limit, transport failure, refusal, truncation, or malformed output closes the request with a typed disposition before marker intake. A new call requires fresh operator initiation. The Phase 3 execution worker retains its network denial.

## Phase applicability

Phase 3 qualified one CLI-approved marker action on preproduction `x64-review`; no provider was introduced. Phase 4, entered 2026-11-24 against the `v0.2.0` baseline, specifies the provider adapter above; the live model-provider path still owes its own evidence. Until a later increment implements it, fixture schema/length tests exercise foundation data only and do not satisfy proposal rejection or audit-event obligations.

The Phase 2 design candidate accepts only the exact NoOp shape and fingerprint domain specified in [ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#2-canonical-binary-v1). It binds task/run, expected task version, policy version, criterion, recovery and approval requirement. Unknown actions, altered bindings or approval-required input fail closed. Phase 2 provides rejection evidence for unsupported approval, not the positive operator approval path required in Phase 3. No provider or real tool is introduced by the design.
