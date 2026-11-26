# Phase 4 entry — model and operator workflow

**Entry authorized by Proto (Ian), 2026-11-24. Adapter and operator-workflow owner: Proto (Ian).** The accepted Phase 3 exit is tagged `v0.2.0` at commit `e2b2fa23d2ce5ba16ac320958be786fc6a7b58dc`, Git tree `1695f992d0845dfcf132e5da4c35dcb1aca04b6d`. Phase 4 connects one reviewed model provider adapter and the operator approval workflow while keeping both outside the authority boundary. Phase 4 may change presentation, but it may not weaken or reinterpret the Phase 3 proposal-binding and acceptance semantics without invalidating Phase 3 approval evidence. Entry takes effect when this owner-reviewed record merges to main. [Phase 3 exit](../governance/phase3-exit.md) · [Phase 4 gates](../governance/PHASE_PLAN.md#phase-4-model-and-operator-workflow)

## Entry decisions

| Gate | Decision |
|---|---|
| Provider and interface | OpenAI Chat Completions with the pinned snapshot `gpt-5.4-mini-2026-03-17`. The adapter exposes one provider-independent operation: submit the approved projection and return bounded, untrusted candidate bytes or a typed failure. Live and fixture responses enter the same local parser. One non-streaming completion, tools disabled. A snapshot change requires profile review; an unavailable snapshot yields a failure. |
| Approval surface | The authenticated local CLI is the only approval surface through v1.0.0. Any remote approval surface requires its own identity and transport review and is out of scope for this phase as entered. |
| Model boundary | The projection contains only a fixed instruction, the proposal schema, an opaque single-use request ID, and an operator-selected intent from a reviewed catalog of public or synthetic marker examples. Free-form operator text, task history, runtime identifiers, paths, tool output, and credentials stay outside the projection. Unclassified fields are rejected before egress. |
| Data handling | Raw provider requests and replies are held in memory for the call only. The normalized proposal and authority evidence are retained under existing custody rules. Failures are audited using the request ID, provider profile, bounded counts, and typed reason. Each request sets `store: false`. Before activation, Proto verifies that voluntary input/output sharing is disabled for the dedicated API project. The provider's documented abuse-monitoring retention is accepted for this public/synthetic projection, including its stated exceptions. A dedicated project credential is readable only by the isolated adapter identity. |
| Proposal schema and limits | Exactly one UTF-8 JSON object, at most 8,192 bytes before parsing, with five required fields: integer `schema_version` equal to 1, `request_id` echoing the issued 32-character lowercase hex ID, `action` equal to `create_marker`, `expected_effect` equal to `marker_contains_payload`, and `payload_b64` holding canonical padded RFC 4648 Base64 for 0–4,096 decoded bytes. The decoded bytes must match the selected public or synthetic example. [Boundary specification](../contracts/model-proposals.md#phase-4-boundary-specification) |
| Request binding | Each request ID is bound locally to one operator intent and consumed at most once, including across restart. Duplicate or unknown keys, wrong types, trailing content, stale IDs, and repeat delivery are rejected before intake. The runtime supplies every authority-bearing field and computes the existing Phase 3 proposal fingerprint from the normalized proposal. |
| Approval and acceptance | The existing authenticated local CLI displays the exact normalized proposal, target, byte length, and full payload digest. The full approval binding is preserved, and any binding change requires fresh approval. The adapter has no registered authority role. Only the registered observer produces effect evidence, the independent evaluator applies runtime-owned criteria to the confirmed observation, and the state boundary accepts once at the expected versions. Provider text claiming approval or success has no effect on any of those steps. |
| Egress | Only HTTPS `POST` to `api.openai.com:443/v1/chat/completions`, TLS 1.2 or later, with certificate and hostname verification. Destination restrictions are enforced outside the adapter process with a trusted resolver; private, loopback, link-local, and reserved destination addresses are denied. Redirects, proxy overrides, and caller-supplied URLs or headers are disabled. The credential is sent only as the bearer token for that endpoint. |
| Egress limits and denial | Serialized request body at most 16 KiB, response headers at most 16 KiB, uncompressed response body at most 64 KiB; compressed responses are declined. Five seconds to connect, 30 seconds total from request start, one attempt. Cancellation, timeout, rate limit, transport failure, refusal, truncation, or malformed output closes the request with a typed disposition before marker intake. A new call requires fresh operator initiation. The Phase 3 worker retains its network denial. |

## First increment

This increment records the [adapter decision](../decisions/0010-provider-adapter-boundary.md), the [proposal contract](../contracts/model-proposals.md#phase-4-boundary-specification) and the [verification obligations](../verification/traceability-matrix.md#phase-4-provider-and-operator-workflow). The project phase declaration stays at 3 until separately authorized runtime activation.

## Increment 1 scope for pure candidate validation

**Baseline.** Phase 4 entry commit `d9dcf84f85c1e3f834bda92461a629960e997e13`, tree `4ccb1ea24813ec5b84d4e3a18fd65ca0cc114306`. The implementation budget proposed for owner review is **three files and 450 added non-generated lines total**, including fixtures, tests and the manifest entry. This scope PR records the design for review.

| Proposed implementation file | Purpose |
|---|---|
| `src/model/candidate.odin` | One provider-independent, pure validator and its result types. |
| `tests/odin/model/candidate_test.odin` | In-memory fixtures exercising the validator's public entry point. |
| `tests/odin-packages.json` | Register the test package and named tests with the existing inventory. |

**Inputs and result.** Supply candidate bytes, the expected issued request ID, and the selected catalog example (identity and canonical bytes). Success returns exactly the matched catalog identity, the proven request-ID echo, and the decoded byte length. The validator compares the complete decoded payload with the example. Future intake obtains its bytes from that trusted catalog entry. Neither a candidate buffer nor a slice into decoded model bytes travels in the success value. Failure returns only a typed rejection.

**Reader.** Check byte length before inspecting UTF-8 or JSON. Read the object member sequence and compare decoded key names while duplicates are still observable. A map that has already collapsed duplicate members cannot establish uniqueness. Accept any member order and JSON whitespace. Require exactly one complete object and inspect the remaining bytes for trailing content. Use the pinned Odin toolchain and its standard library.

**Fixture acceptance criteria.** Each negative fixture isolates one fault and asserts the exact rejection. Existing marker codec fixtures begin with runtime-owned records and cannot exercise this untrusted JSON boundary. These cases cover WB-CON-002 and the parser portions of WB-NEG-001/002/012.

| Expected result | Fixture |
|---|---|
| Success | Valid empty example and exact 4,096-byte example. Check all three result fields. A valid object padded with JSON whitespace to exactly 8,192 bytes also succeeds. |
| `CandidateTooLarge` | 8,193 bytes with an invalid first byte, proving size takes precedence over decoding. |
| `InvalidUtf8` | Within the size limit, supply an invalid UTF-8 sequence. |
| `InvalidJson` | Malformed JSON or a top-level value other than an object. |
| `TrailingContent` | Append a second value or a non-whitespace byte after a complete valid object. |
| `MissingKey` | Omit a required member. |
| `UnknownKey` | Add an unrecognized member to an otherwise valid object. |
| `DuplicateKey` | Repeat a known key with identical values, then with conflicting values. Include an escape-equivalent spelling such as `action` and `\u0061ction`. |
| `WrongFieldType` | Supply an incorrect JSON type for each field, including a boolean for the integer version. |
| `UnsupportedSchemaVersion` | Supply integer version 2. |
| `WrongAction` | Supply an unregistered action string. |
| `WrongExpectedEffect` | Change only the expected effect string. |
| `RequestIdMismatch` | Change one digit, or uppercase a hex letter of the issued lowercase ID. |
| `NonCanonicalBase64` | Exercise missing required padding, embedded whitespace, a character outside the alphabet, and nonzero unused pad bits. |
| `DecodedPayloadTooLarge` | Supply canonical Base64 encoding 4,097 bytes within the candidate cap. |
| `PayloadMismatch` | Mutate one byte of the exact 4,096-byte example, preserve its length and re-encode canonically. |

**Verification and handoff.** Run the new Odin package with vet and warnings as errors, then verify its named inventory and run documentation governance checks. The pure validator observes only supplied values. Repeat validation against identical inputs gives the same result. Durable ID consumption and crash disposition belong to increment 2. Provider envelope handling, project-settings verification and egress belong to increment 3. Marker intake and runtime activation retain their separate gates.

## Increment 2 design decision

Proto selected atomic SQLite consumption with the kind-11 proposal insert. [ADR-0011](../decisions/0011-atomic-model-request-consumption.md) records durable issuance before egress, explicit provisioning, crash dispositions and the evidence owed before integration.

The [approved increment 2 implementation scope](phase4-increment2-scope.md) compares catalog and issuance witnesses, records implementation budgets, and defines the real-path acceptance tests.

## Increment 3 implementation scope

The [adapter and egress scope](phase4-increment3-scope.md) records the approved one-shot transport, conditional libcurl qualification, package budgets, denial fixtures and the handoff from isolated qualification to separately authorized live evidence.

## Exit obligations retained

Phase 4 exit still owes live provider and egress evidence, deterministic fixture reproduction, approval-binding regressions, WB-NEG-001 through WB-NEG-012 coverage on the real path, and explicit rejection of learned promotion under WB-CON-010 and WB-INV-010. The ADR-0006 disposition and the production-target rerun remain due at their recorded gates and are not Phase 4 entry blockers.
