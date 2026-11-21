# ADR-0005 Event integrity acceptance and recovery

- **Status:** Accepted
- **Decision owner:** Proto, project owner (assigned 2026-10-18)
- **Review status:** Accepted by Proto; implementation entry recorded separately
- **Acceptance date:** 2026-11-10
- **Acceptance authority:** Proto (project owner)
- **Acceptance record:** https://github.com/progentic/Warband/commit/f46ae949ee84d1a1848fe7519363b0d47600a422
- **Accepted source:** 84cfc937a88c55d01e4e620337bf20f63afe3b1e
- **Scope:** Phase 2 deterministic no-op authority boundary
- **Supersedes:** None
- **Related decisions:** Accepted ADR-0001 through ADR-0004 and ADR-0007; ADR-0006 remains Proposed
- **Authorization:** Design acceptance only. Phase 2 implementation requires the separate entry record in the Phase 2 entry review.

The acceptance record was verified in protected main at `d26927568078980ee8037d1d79a7c86f5fcbdd2b` before activation. Acceptance covers the complete amended design; historical candidate labels below do not claim implementation. Phase 1 debts and later production gates remain open.

The owner requested progression to the next phase on 2026-10-18 and assigned Proto as this decision's owner. [Phase 2 entry review](../engineering/phase2-entry-review.md) records the outstanding decisions and proposed review sequence. Owner assignment does not accept this ADR or resolve its implementation gates.

[Accepted ADR-0008](0008-phase2-resource-limits.md) tracks WB-EXC-001 and records provisional resource limits, review and expiry conditions for the accepted denial-growth limitation. Its structured fields hold the exception disposition; acceptance of this historical design remains recorded above.

## Accepted live capability clock amendment

**Accepted by Proto on 2026-11-21.** This ruling binds the provisional capability lifetime in [ADR-0008](0008-phase2-resource-limits.md) to Linux elapsed time. The live adapter and dispatch wiring require separate implementation authorization.

Start the 90-second interval when authorization construction begins. Take a fresh Linux `CLOCK_BOOTTIME` observation at claim confirmation and again immediately before dispatch. Each observation must be **strictly before expiry**. At or after expiry, or on a missing or regressing observation, withhold dispatch. The wall-clock expiry in the authorization event is audit evidence only.

An incarnation is one execution of the issuing runtime. Keep the live grant and its elapsed-time origin only in that execution's private memory. Dispatch requires that entry as well as durable authorization and the confirmed claim. Each startup begins with an empty live-grant set. Replay can reconstruct audit facts but cannot populate that set. The 180-second task deadline ends with the issuing execution. Reconcile in-flight tasks from durable evidence and withhold automatic redispatch. A separately authorized new task receives a new identity and deadline.

The [isolated Linux gate proof](#isolated-no-op-live-dispatch-qualification) exercises fresh-runtime denial using a prior grant’s durable evidence. Suspend accounting rests on the documented kernel behavior: with 20 seconds remaining, a 5-second suspend leaves 15 seconds, and a suspend of 20 seconds or longer expires the grant. Warband has no target suspend test. [Linux kernel timekeeping](https://docs.kernel.org/core-api/timekeeping.html)
macOS Phase 2 evidence covers supplied-clock decisions only. There is no macOS live capability adapter in Phase 2.

Resource overrun uses the proposed capped recovery/readiness checks; no persistent latch or new custody metadata is proposed. Epoch rotation retains custody ordinals and complete-history authorization uniqueness. An archive-and-new-store closure path needs a separately reviewed predecessor-head binding and archive-verification procedure beyond the current genesis format.

## Owner acceptance decision recorded 2026-11-10

The project owner, Proto for this decision, explicitly authorized the assistant to record acceptance: "Rufus, I approved that and I want you to accept it. I am authorizing you to accept that ADR and then to begin the phase 2 implementation."

This records the owner's acceptance of ADR-0005's complete amended design at reviewed source `84cfc937a88c55d01e4e620337bf20f63afe3b1e`, including the selected Option A and its recorded aggregate denial-history growth limitation. The assistant records the owner's decision on his behalf; this is not an independent agent or security-review approval.

This commit records the Gate 2 decision only. Its actual commit must be verified in protected main before filling the acceptance provenance fields and activating Phase 2. Gate 3 entry is recorded separately. No implementation result, debt closure or production release is claimed.

## Pure epoch advancement follow-on recorded 2026-11-10

The project owner authorized this seven-file increment, requested this ADR record, and reviewed the three focused cases before test implementation. The baseline is `95b2a4bff5a53b1ebc53c6da1a5885a5d2a2b8d5`; the increment stays below 100 added lines. This implementation record does not change the accepted design or its original acceptance provenance.

Epoch advancement must stop rather than create an invalid identity. The pure `next_epoch` rule returns the supplied epoch plus one, rejects zero with `EmptyEpoch`, and rejects the maximum value with `EpochOverflow`. It grants no operator authority, enrolls no store and changes no custody or runtime state. Actual epoch administration remains deferred.

Changed files and decisions:

- `src/domain/events/identity.odin`: add only the typed arithmetic rule and overflow error.
- `tests/odin/event_identity/event_identity_test.odin`: add one test with normal advancement, zero rejection and overflow rejection only.
- `tests/odin-packages.json`: declare that test in the existing package.
- `AGENTS.md`: recognize the separately authorized pure follow-on without widening effect permissions.
- `docs/engineering/phase2-entry-review.md`: record the bounded scope extension.
- `docs/verification/traceability-matrix.md`: record partial domain coverage without closing runtime gates.
- `docs/decisions/0005-event-integrity-acceptance-and-recovery.md`: preserve this decision and file-change record.

Test necessity: invalid or wrapped epochs would violate amendment section 1. Existing tests cover references and sequence advancement, not epoch advancement. The new test removes that gap for the implemented rule at the cost of one small test, three cases and no dependency. It does not speculate about future administration, custody, storage or replay behavior.

Verification of this local increment on native macOS ARM64: pinned compiler and artifact identity, Warband build with vet/warnings-as-errors, documentation governance, all 26 Python controls, all three Odin packages/eight named tests, CLI smoke and diff checks pass. These local results establish no Linux, hosted, administration, durability or replay result. The owner subsequently authorized commit and push to main through the protected PR process, waiting for GitHub runners; hosted results must bind to the exact published head.

## Pure prepare classification follow-on recorded 2026-11-10

The owner approved this seven-file, under-100-added-line increment and its focused cases before implementation, against `e192539d8e960e9b7004ede0f4d3b5228d8b68a9`. `Pledge` and `Checkpoint` are bounded domain values, not wire layouts. Pure `classify_prepare` checks explicit identity, next sequence, committed predecessor and exact pending binding. Its outcomes distinguish eligibility, exact pending replay and typed rejections. Eligibility grants no authority: authentication, link verification, history validation and durable writes remain separate unimplemented gates. The decision reads supplied values only and never replaces a pending pledge.

Test necessity: ADR-0005's prepare rule must reject requests that change a live pledge or its scope/order. Existing tests cover identity/arithmetic, not prepare classification. One new test covers only eligible next request, exact pending replay, changed pending request, wrong scope, wrong predecessor and skipped sequence. This removes the implemented decision gap with no dependency or framework; it proves no persistence, authenticity or durability behavior.

Changed files: `src/domain/events/prepare.odin` adds these values and the pure classifier; `tests/odin/event_identity/event_identity_test.odin` adds that focused test; `tests/odin-packages.json` declares it; `AGENTS.md` and `docs/engineering/phase2-entry-review.md` record the bounded extension; `docs/verification/traceability-matrix.md` records partial domain coverage; this ADR records the decisions and file changes. No effect permission or accepted design is changed, and publication requires separate authorization.

The owner subsequently requested a changelog update and commit/push to main, then explicitly approved the expanded eight-file, up-to-110-added-line publication scope. `CHANGELOG.md` adds the dated `0.1.0-dev.1` development entry; it does not declare Phase 2 complete or authorize a tag/release. The other seven files, code and six cases are unchanged in scope. Publication follows the protected PR process and exact-head checks.

Native macOS ARM64 verification: pinned compiler/artifact identity, build with vet/warnings-as-errors, documentation governance, all 26 Python controls, all three Odin packages/nine named tests, CLI smoke and diff/scope checks pass. These local results establish no hosted, Linux durability or runtime custody result; hosted results must identify the exact published head.

## Pure confirm classification recorded 2026-11-11

The [entry review](../engineering/phase2-entry-review.md#pure-confirm-classification-authorized-2026-11-11) records the owner-approved bounded slice. `classify_confirm` reuses identity and prepare checks, compares the complete latest committed tuple against the supplied committed checkpoint, and gates eligibility/replay on head publication. Latest committed replay reads but never clears a newer pending pledge. Supplied metadata must come from future authenticated and validated custody observations; classification itself grants no authority or durable receipt.

The owner subsequently authorized committing and publishing this slice to main with a concise next-patch changelog entry. Version `0.0.4` records the classifier and ADR-0008 adoption; `0.0.3` remains reserved for the separate governance cleanup. Publication uses the protected PR path.

## Pure recovery classification recorded 2026-11-12

The [entry review](../engineering/phase2-entry-review.md#pure-recovery-classification-authorized-2026-11-12) records the seven-file, 150-line authorization. `classify_recovery` implements supplied-value READY, PENDING_EVENT_MISSING, PENDING_CONFIRMATION, UNATTESTED_TAIL, INTEGRITY_FAULT, STORE_IDENTITY_MISMATCH and EPOCH_MISMATCH. Journal-behind, conflicting heads and changed pledged tuples are integrity faults; an unpledged or extra suffix is unattested. Store/epoch mismatch takes precedence. The procedure reads existing domain values and reuses prepare validation without mutating state.

This slice assumes validated custody metadata and a verified checkpoint-covered prefix. Parsing, hashing, storage, publication recovery and actual recovery actions remain separate future boundaries. A returned READY classifies these observations only and grants no execution or state-transition authority.

The owner authorized publication of the recovery slice through a PR after checks pass, with the concise `0.0.5` changelog entry dated 2026-11-12.

## Pledge encoding and link hashing recorded 2026-11-12

The owner approved local Mac development of the fixed pledge codec and SHA-256 link, with focused golden, round-trip, malformed-length and tampering checks, approximately 8–10 files and 200–250 added lines. This increment uses baseline `77cfc6a2cd6cc739f602dbaa1402026ceaf0eead`; no commit, push, tag or release is authorized by this scope.

`src/custody/pledge.odin` encodes exactly the existing 136-byte tuple and hashes exactly the 112-byte link input, including the domain's final zero byte. Encoding and decoding require explicit expected store/epoch, valid event identity, next sequence and matching link; typed failures return no partial value. No native struct serialization, allocation, format fallback or input mutation is used. Hash equality binds the supplied digest; it does not verify that digest against persisted event bytes or establish authenticity.

Public codecs are pure Mid decisions using pure value validation and Low endian/SHA-256 helpers. The pinned Odin SHA-256 library selects acceleration from its standard-library CPU-feature cache; codec/hash calls perform no filesystem, network or clock I/O. Review identified the library's startup observations, and the owner explicitly approved only the [narrow CPU-initialization qualification](#pinned-sha-256-library-startup-qualification--approved-2026-11-12) below. No application runtime effect or cryptographic algorithm is added. Full event/frame codecs, custody, storage and runtime authority remain unimplemented.

Before this codec was written, independent Python 3.15.2 field-table construction matched 28 byte/hash comparisons from `adr0005-golden-vectors.json`; every digest was cross-checked with OpenSSL 4.1.0. Reproduction used fixed IDs, little-endian fields and exact domains, not Warband code. The tuple is 136 bytes, head file 134 and denial frame 203; the linked head is `00e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f`.

Two tests in `tests/odin/custody/pledge_test.odin` close the previously unimplemented byte/hash boundary: one compares literal specification bytes/hash and round-trip, the other rejects short/excess bytes and identity, sequence and digest tampering. They use the existing runner and standard library only. `tests/odin-packages.json` retains all eleven prior tests. The other changed files are `AGENTS.md`, the entry review, traceability matrix, package boundaries, developer guide, maintainer guide and this ADR; accepted wire rules and runtime verification status are unchanged.

Native macOS ARM64 validation of this working increment passes pinned compiler/artifact identity, build with vet/warnings-as-errors, documentation governance, all 28 Python controls, all four Odin packages/thirteen named tests, CLI smoke and diff/scope checks. This is local functional encoding/hash evidence only; no hosted/Linux, custody authenticity, storage durability or complete Phase 2 result is claimed. The work remains uncommitted and unpublished.

## TaskCreated canonical codec recorded 2026-11-13

Proto authorized eleven files and up to 300 additional lines on the existing uncommitted pledge increment. The implementation covers only kind 1/producer 1/version 1: 56 header bytes, 96 payload bytes and 32 previous-head bytes. Explicit little-endian writes avoid native-layout dependence. Fixed-size output and exact-length decoding enforce this kind's bound; unsupported schema/kind/producer versions and malformed headers return typed errors with zero output. Expected store/epoch and nonzero event/payload identifiers are validated in both directions.

`src/domain/events/identity.odin` adds distinct 16-byte TaskId, RunId, CommandId and EvidenceId; Phase 1 fixture IDs remain separate. `src/audit/task_created.odin` owns the typed representation, encoding, decoding and domain-separated body digest. The existing custody link function binds that digest and previous head. Digest changes detect byte differences only when compared with trusted evidence; input-digest semantics, producer authenticity and accepted facts remain future verification boundaries. Public APIs are pure supplied-value decisions; fixed endian operations and the previously approved SHA-256 startup qualification cover their technical dependencies.

Independent Python struct/hashlib construction reproduced the 96/152/184-byte payload/body/event, event digest `e77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035` and linked head `00e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f`. OpenSSL independently matched both hashes before implementation. Literal golden and negative vectors come from `adr0005-golden-vectors.json`; expected bytes are never generated by the codec under test.

Two tests in `tests/odin/audit/task_created_test.odin` verify exact bytes/digest/link, decoding and changed-body hashing, plus supplied unknown-schema/truncation vectors, trailing bytes, magic/payload-length errors, kind/producer rejection, zero identifiers and scope mismatch. These close the newly implemented canonical-byte boundary; existing pledge tests cover a different representation. The manifest retains all thirteen earlier tests and declares five packages/fifteen tests. Supporting scope, package ownership, traceability and developer/maintainer guidance are updated within the approved eleven files.

Failure record: focused attempt 1 failed at compilation because Odin rejected array literals directly in range-loop headers in the new test. Replacing those headers with named arrays corrected syntax without weakening assertions. Focused attempt 2 passed both tests with vet and warnings-as-errors. Raw command output is retained in `.local/task-created-review/focused-attempt1.log` and `focused-attempt2.log`; independent reproduction is in `vector-reproduction.log`. These local logs are working evidence, with hosted/Linux verification pending.

Broader validation initially failed before running adjacent packages because the manual invocation passed relative `tests/odin` to `discover_packages`, whose paths must be relative to its absolute repository root. The corrected invocation uses `ROOT / 'tests/odin'`. `adjacent-packages.log` retains the failed invocation; `adjacent-packages-attempt2.log` records six event-identity and two pledge tests passing plus exact manifest inventory. All 28 Python governance controls pass (`governance-tests.log`), and documentation governance passes (`governance-docs.log`). Command recipes and the complete failure summary are retained in `.local/task-created-review/validation-record.md`; scope comparison confirms the pledge source/tests remain byte-for-byte intact.

The [2026-11-15 evidence addendum](../verification/task-created-evidence-addendum.md) records the retained bundle, exact test names and vector values, retrospective hashes, scope reconciliation, reproducible commands and limits of historical provenance.

## Codec publication authorized 2026-11-13

The owner subsequently authorized publishing the local pledge and TaskCreated codec increments to main. The earlier local-only scope and pending-hosted statements describe their original verification points. Publication follows the protected PR path, with hosted results tied to the published source.

## Custody frame and head codecs recorded 2026-11-15

Proto approved eleven files and up to 400 added lines for PENDING/COMMITTED frames and head-file bytes. `src/custody/frame.odin` composes the existing pledge codec with a fixed 51-byte header, 32-byte header hash, 136-byte pledge and 32-byte record hash (251 bytes). `src/custody/head.odin` encodes the fixed 134-byte materialized head. Typed errors return zero values. Existing pledge source and tests remain unchanged; only the standard endian/SHA-256 dependencies already qualified above are used.

Frame decoding requires explicit expected store/epoch, custody ordinal and previous record hash. Ordinal zero rejects; ordinal 1 requires a zero predecessor. Every present fixed header byte and header-hash byte is checked before reporting truncation. Complete checksum corruption is ATTESTATION_HISTORY_FAULT, including the published negative vector. Truncated is a byte-shape result: only later history/recovery validation can establish that it is the final frame and that repair preserves the published head. These APIs never repair, authenticate, validate enrollment, pair COMMITTED with a pending record or authorize progress.

The head codec validates magic/version, exact size, checksum and expected store/epoch. Sequence zero remains representable for genesis/epoch metadata; callers establish enrollment and bind the committed-record hash to validated custody history. The shared private hash helper covers the three fixed metadata domains including their final NUL. Formatting errors are local typed results; recovery policy and wire status selection remain separate.

Independent field-table construction first reproduced both frame bytes, header/record hashes and head bytes/checksum using Python struct/hashlib and OpenSSL. PENDING hash is `9f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4`; COMMITTED hash is `8ea5a61a02677828bac5ae7b85bd662d5934fc1851a960b7aa6f7b416f475005`; head checksum is `07119d52184d55b10a24ca2ef1c1eff31f8d2a75490a52676d69671476b08faa`. The ordinal-1/2 vectors are isolated framing examples, not an enrolled history. The negative checksum vector failed independent hash comparison as expected.

Three focused tests cover both frame golden vectors and head round-trips; consistent truncation versus prefix/header/hash corruption, schema/kind/length/scope/ordinal/predecessor rejection; and head checksum/scope/length checks including sequence-zero representation. These exercise the implemented byte boundaries while existing pledge tests retain link validation. The manifest declares five packages/eighteen tests. Other event kinds and GENESIS/EPOCH/REJECTION payload codecs remain future slices.

Evidence is retained under `.local/custody-frame-review/`: `reproduce.py`, `reproduction.log` and `reproduction-status.json` precede implementation. Each focused attempt retains source snapshots, SHA-256 source/compiler hashes, exact command, exit code, output and JSON report. Focused attempt 1 exited 0 with all five custody tests passing; no compile or test failure occurred in that attempt. These are native macOS functional checks; hosted/Linux and persistence evidence remain separate. Broader validation passed eight adjacent audit/event-identity tests, all 28 Python governance controls, documentation governance and whitespace checks. `validation-results.json` retains each command and exit code; adjacent JSON reports and compiler identity output are retained beside it.

Meta reported independent verification of bundle `4988e828724fec5e0b38995847d42c660a114ab6add917c1c74a04bcdf1c80a9`, exact 11-file/356-line scope, vector reproduction, pledge preservation and all 28 governance controls, with no blocking code-review defects. Meta's independent Odin execution remained pending. The five untouched foundation/negative tests were outside the local 13-test run. This subsequent review/publication note extends the documentation beyond that reviewed bundle; its code and tests are preserved. The owner authorized publication through the protected main path after review.

## GENESIS, EPOCH and REJECTION payloads recorded 2026-11-15

Proto approved fourteen files and up to 700 added lines for pure payload codecs and specified hashes, following the eight semantic rulings reviewed with Meta. `genesis.odin`, `epoch.odin` and `rejection.odin` reuse existing checkpoint, endian, metadata-hash and checked epoch-advancement logic. Domain vocabulary gains a distinct 16-byte AuthorizationId. No existing pledge/frame/head API is changed; decode_frame still rejects kinds 3–5. These payloads supply no enrollment, authentication, authorization-uniqueness, pending-state, persistence or recovery-operation proof.

GENESIS history bytes append the operator UID to enrollment bytes; genesis_head hashes only enrollment. Epoch encoding derives new_epoch through next_epoch, writes zero new_seq, and computes new_head from exactly old Ref, old head, new epoch, authorization ID, counted reason and unresolved-pending hash. Decoding verifies advancement and new_head. The epoch hash excludes new_seq, new_head and operator UID. Invalid advancement/overflow maps to Malformed; bad head binding maps to InvalidChecksum. Payloads retain explicit expected store/epoch checks, with GENESIS epoch fixed at 1.

GENESIS/EPOCH encoders return fixed 1074/1194-byte capacity buffers and explicit used lengths. Reasons are owned 1024-byte arrays with a used length; unused capacity is excluded from encoding/hash inputs. Both directions require 1–1024 bytes of valid UTF-8 without NUL, using the pinned standard-library utf8 validator. Decoders copy reason bytes into their returned value; production APIs allocate no heap storage. Root UID zero remains valid.

REJECTION uses exactly 88 bytes, nonzero store, explicit expected epoch including zero, fault codes 1–19, flags 0/1 and capture length at most 65547. Unobserved peers require all UID/GID/PID fields zero; observed peers may have zero identifiers. denial_digest hashes the domain, u32 length, complete flag and supplied prefix. A decoded digest is an opaque binding value whose provenance and agreement with captured input require the later trusted acquisition path.

Independent Python field-table construction and OpenSSL checks preceded Odin implementation. The new specification keys genesis_history and epoch_changes retain the existing vectors and add a UID-suffixed GENESIS example plus EPOCH examples with zero and nonzero pending-hash bindings. The EPOCH heads are `9fe9418f55e10e99815d6efe322509d4d891276b007b130eb66225472a573802` and `789be34508f45f8144db0001415d4653351e6117b10771660d7e5fa01974772c`. These are byte/hash examples, not evidence of an eligible administrative history. No GENESIS or EPOCH frame vector is claimed.

Reproduction attempt 1 failed because the review description was interpreted as saying the published REJECTION payload used epoch zero. Inspection found byte 16 encodes epoch 1; its denial digest already matched. Attempt 2 used epoch 1 and matched the published payload unchanged. Epoch-zero support is tested separately under the ADR rule. Logs, recipe hashes and exit codes are retained under `.local/custody-admin-review/attempt1-*` and `reproduction*`.

Six focused tests compare exact payloads, hashes and round-trips, then exercise implemented identity, reason, length, advancement/overflow, hash-binding, flag, capture and peer-field boundaries. Existing pledge/frame/head tests remain intact. Codec attempt 1 stopped before tests on two redeclared test error variables; attempt 2 passed all eleven custody tests after those variables were renamed. Production source hashes match across those attempts. Per-attempt source snapshots, commands, compiler hashes, raw outputs and JSON reports are retained under `.local/custody-admin-review/codec-attempt*/`. Native results establish functional encoding only; hosted/Linux and operational authority remain separate evidence.

After prefix-byte/completeness mutation assertions were added, codec attempt 3 ended in compiler SIGSEGV before any test report. The retained macOS crash report identifies alloc_cstring/lb_type_internal during LLVM generation; the root cause remains unresolved. Attempt 4, with identical source/compiler hashes, passed all eleven custody tests. No assertion or production code was changed to obtain that retry result. Broader checks passed eight adjacent audit/event-identity tests, all 28 Python governance controls, exact manifest inventory, vector reproduction and whitespace checks; commands and exits are in validation-results.json. The five untouched foundation/negative tests were outside this local run.

The owner subsequently authorized main publication of this payload slice through the protected PR path. The reviewed local bundle has SHA-256 `cf74d3f86e85d43cb322e1caba1148c68580c85591cb6eae9de9d6ef284f4223`; this two-line publication note extends its documentation while preserving its implementation and tests. Hosted checks must bind to the published source.

## All-kind custody framing authorized 2026-11-16

Proto approved up to twelve files and 500 added lines for a shared framing core that delegates all five payload kinds to the existing codecs. `encode_record`/`decode_record` use an owned CustodyRecord payload union and FrameEncoding with zero-initialized fixed capacity plus explicit length. Kind/payload mismatches reject. Legacy encode_frame/decode_frame remain fixed 251-byte PENDING/COMMITTED entry points through the same core. Existing payload APIs and head-file handling retain their behavior.

The exact overhead is 51 bytes (magic 4, version 2, kind 1, length 4, ordinal 8, predecessor 32) plus header hash 32 and record hash 32, totaling 115. GENESIS history has 50 fixed bytes plus 1–1024 reason bytes, maximum 1074; EPOCH has 170 fixed bytes plus the reason, maximum 1194. Thus maximum frame capacity is 1194+115=1309, independently of example sizes. Only returned lengths enter hashes, comparisons or exposed slices; the unused tail stays zero.

The shared decoder bounds declared lengths by kind, including partial little-endian lengths, before slicing payloads. Every available fixed prefix/context/hash byte is checked before returning Truncated. Complete corruption maps to AttestationHistoryFault. Payload failures preserve their existing FormatError result, with legacy pledge failures retaining InvalidPledge. Ordinal/predecessor rules apply uniformly; enrollment and history sequencing are caller responsibilities. A decoded record is format-valid data, not authenticated custody or authoritative state.

Independent Python struct/hashlib construction with OpenSSL cross-checks added complete GENESIS and two EPOCH framing examples and reproduced the existing REJECTION frame. New rejection fixtures have valid outer hashes and invalid payload fields, isolating payload error propagation. GENESIS frames cover the full UID-suffixed history payload in their record hash. Since that payload contains no genesis-head field, frame decoding cannot reject a separately miscomputed genesis-head hash; the existing genesis_head tests enforce UID exclusion. The new wrong-representation fixture uses enrollment-only bytes and rejects the impossible GENESIS history length.

Two focused tests cover all new golden bytes/hashes and round-trips, zero tails, maxima and one-byte-over cases, kind-specific truncation/length/trailing rejection, shared corruption/context rejection once, and one invalid payload per new kind. Existing PENDING/COMMITTED regression assertions remain intact. The manifest declares five packages/twenty-six tests. Header and hash logic has one implementation; payload semantics remain in the reviewed codecs. No history mutation, repair or administrative authority is added.

Evidence is retained in `.local/all-frame-review/`. `reproduce.py`, its output and recipe hash record independent construction. Focused attempt 1 failed compilation because Odin requires unsigned shift operands in the partial-length check. Explicit unsigned casts corrected that type error; attempt 2 passed all thirteen custody tests with vet/warnings-as-errors. Each attempt retains source snapshots/hashes, compiler hash, command, exit code, output and JSON report. Attempt 3 added the possible/impossible partial-length prefix assertions and again passed thirteen custody tests. Broader validation passed eight adjacent tests, all 28 Python governance controls, inventory, reproduction and whitespace checks; validation-results.json retains their commands and exits. This is local macOS functional evidence; hosted/Linux verification remains pending.

Prepublication review on 2026-11-16 ran the full manifest: all five packages/twenty-six tests passed, exit 0. Five additional identical custody build/test invocations passed thirteen tests each, with unchanged source/compiler hashes, flags and command; the earlier compiler SIGSEGV did not recur, and its root cause remains unresolved. The new explicit 1309 constant assertion, maximum-frame round-trips, one-byte-over Malformed results and zero-tail assertions passed. Independent inspection confirmed the enrollment-only GENESIS fixture has valid outer hashes/context and a 48-byte payload, so the history-payload minimum (51) is its rejecting condition. Source snapshots, exact commands, exits, fresh JSON reports and boundary-audit.json are retained under `.local/all-frame-review/prepublication/`. These are native macOS functional results; hosted/Linux verification remains open.

The owner subsequently authorized publishing this increment through a PR after all hosted checks pass. The prepublication evidence archive has SHA-256 `de5926c4fb934ee6b897d0d80cdbb75067938588f99f1be5b2144d34ed500790`. This two-line publication note extends its documentation while preserving the tested implementation and assertions.

### Deferred obligations after all-kind framing

The [Phase 2 verification plan](../verification/phase2-verification-plan.md) remains the source of the later proof gates. This codec increment leaves the following obligations open:

- Validate complete custody history, enrollment/epoch ordering, authorization-ID uniqueness and COMMITTED/PENDING pairing; reconcile the head and retain all applicable diagnostics.
- Establish that a truncated frame is final, repairable and consistent with the published head before any repair; implement and fault-test append/fsync/rename/directory durability and lost-response recovery.
- Authenticate runtime/operator peers, protect custody files/endpoints, derive observed peer metadata from the OS, and reconcile denial receipts into the event store exactly once.
- Implement the remaining event kinds and socket request/reply formats, SQLite integration, no-op authority/evidence path and deterministic replay under their scoped authorizations.
- Implement the accepted live capability clock rule and verify [fresh-runtime dispatch denial](../verification/phase2-verification-plan.md#fresh-runtime-dispatch-denial).
- Resolve WB-EXC-001 at its expiry gate, production target evidence, foundation debt and independent closure review.

## ProposalRecorded codec authorized 2026-11-16

Proto approved thirteen files and up to 400 added lines, with shared envelope/event hashing, unchanged TaskCreated tests, independent vectors first and two focused tests. `src/audit/envelope.odin` owns the current producer-1/version-1 header and domain-separated hash operations. TaskCreated delegates to it while retaining its public representation, sizes and typed errors. `proposal_recorded.odin` adds kind 2 with a 75-byte payload, 131-byte body and 163-byte event, using existing task/run/reference types plus distinct ProposalId. AGENTS.md is unchanged under the owner's instruction; this dated record authorizes the new pure representation.

The encoder fixes action=NoOp, target=none, argument length=0, criterion=NoOpV1 and recovery=stop/reconcile. Both directions require explicit expected store/epoch, nonzero IDs/task version and policy version 1. Approval is a bool in the typed value; decoding rejects bytes other than 0/1. Payload-length errors and zero task version are Malformed; unsupported constants/policy/flags are Unsupported; invalid identity/scope is InvalidIdentity. Failures return zero values.

The proposal fingerprint hashes exactly the encoded payload slice, including TaskId, RunId and ProposalId. It binds this recorded proposal's payload, including those identities, rather than defining a content-only fingerprint. A shared serialization supplies both event bytes and fingerprint input. The codec checks representation and specified constants only. It does not establish task existence, current expected version, ProposalId uniqueness or denial of approval-required requests; those remain state and authorization obligations.

Independent Python struct/hashlib construction and OpenSSL checks preceded codec implementation. Two proposal_recorded specification vectors reuse the published TaskCreated task/run/store/epoch, previous linked head and recorded time 0, with sequence 2 and expected task version 1. They are alternative encoding examples, not an accepted history. The payloads differ only in the approval byte. Their fingerprints are `c2406d9f939ac81bf762471f3ef5d5c985f844ee46bce010232b1afbdb57a679` and `cac5e293f45379b0f7a07cf0f373ae3e957c27c56c2e224fb4645ac1e28c276b`; body digests and linked heads are also independently recorded.

The first test checks both golden bytes/digests/fingerprints/heads, round-trip and ProposalId mutation. The second checks cross-kind rejection, payload length, each named NoOp constant, policy version, zero payload IDs/task version, approval byte 2 and scope/encoder rejection. Existing TaskCreated tests cover shared header failures without modification. The manifest declares five packages/twenty-eight tests; other event kinds and runtime authority remain future slices.

Evidence is retained under `.local/proposal-codec-review/`. Independent reproduction exited 0. The initial TaskCreated refactor compile failed under vet because a local err declaration shadowed another err; renaming that local corrected the issue without changing either existing test. The unchanged TaskCreated tests then passed before the new codec was added. The first combined audit run passed all four named tests. Broader validation passed thirteen custody and six event-identity tests, all 28 Python governance controls, inventory, reproduction and whitespace checks. The five untouched foundation/negative tests were outside this local run. Logs, commands, exits, source snapshots, compiler/test hashes and JSON reports are retained; this is local macOS functional evidence, with hosted/Linux verification pending.

The owner subsequently authorized ProposalRecorded publication through a PR after all hosted checks pass. The local evidence bundle has SHA-256 `a68128d78058539d759001ec2fb6996863c4977728efcfe2574ffbf91169eff3`; this two-line publication note extends its documentation while preserving its tested implementation and assertions. Hosted evidence must identify the published source.

## AuthorizationRecorded codec authorized 2026-11-16

Proto approved the bounded codec with shared envelope reuse, unchanged TaskCreated/ProposalRecorded tests, independent vectors first and focused rejection cases. The implementation uses twelve files within the 400-added-line ceiling: the eleven core/code/evidence records plus the package-boundary module listing. AGENTS.md and the developer/maintainer guides remain untouched. The shared envelope now takes an explicit producer argument; existing callers pass 1 and AuthorizationRecorded passes 2, all at producer version 1.

`authorization_recorded.odin` encodes kind 3 as an 82-byte payload, 138-byte body and 170-byte complete event. A flat typed struct mirrors the wire. Both directions validate nonzero event/proposal references in the expected store/epoch and a nonzero EvidenceId; CapabilityId is a new distinct 16-byte domain type. Control revision zero is representable. Decision 1 requires a nonzero capability, use limit 1 and expiry strictly greater than recorded time. Decisions 2/3 require zero capability, expiry and use limit. Decode returns a typed value only after validation; failures return zero output. Unknown decision/producer is Unsupported, invalid identities are InvalidIdentity, and conditional-field contradictions are Malformed.

This slice assigns detectable self/forward proposal references to the codec: proposal sequence must be strictly less than the event sequence, otherwise Malformed. Resolution to an actual ProposalRecorded event, task existence, current control revision, capability uniqueness/consumption, producer authenticity and approval-required permit rejection remain later state/authorization obligations. The codec compares recorded integers only and reads no clock; ADR-0008's provisional 90-second lifetime is not enforced here. No authorization fingerprint is defined. This slice computes the event digest and composes its linked head through the existing custody function; DispatchClaimed carries the proposal fingerprint later.

Independent Python struct/hashlib and OpenSSL reproduction added three alternative sequence-3 encoding examples, not accepted histories. Permit and reject continue approval-0's published proposal head; require-approval continues approval-1's head. All reference the matching store/epoch/sequence-2 proposal. Revision `0x0807060504030201`, recorded time `0x0001020304050607` and permit expiry `0x0102030405060708` expose multi-byte byte-order mistakes. Nonzero revision is an encoding example only; no current-state match is claimed. Zero revision and expiry equal/plus-one boundaries are separately tested.

Two focused tests cover golden payload/event bytes, digest, linked head and round-trip for all decisions, then decision values 0/4, conditional capability/expiry/use-limit violations on encode and decode, zero evidence/proposal-store/sequence, wrong proposal store/epoch, self/forward references, cross-kind inputs and producer 1 on kind 3. Existing header-rejection tests remain byte-identical. The manifest declares five packages/thirty tests. Existing four audit tests passed immediately after the producer-parameter change; all six audit tests passed on the first combined build.

Evidence is retained under `.local/authorization-codec-review/`: independent reproduction recipe/output/hash, regression command/exit, and the combined run's source snapshots, compiler/source hashes, exact command, exit 0, output and JSON report. No compilation or test failure occurred in these runs. Broader validation passed thirteen custody and six event-identity tests, all 28 Python governance controls, exact inventory, reproduction, documentation and whitespace checks. The five untouched foundation/negative tests were outside this local run. Commands, exits and reports are in validation-results.json. These are native macOS functional results; hosted/Linux and runtime authority verification remain separate.

The owner subsequently authorized AuthorizationRecorded publication through a PR after all hosted checks pass. The local evidence archive has SHA-256 `0f551f567afc0562123684ac2be68ac5756e49fbb7574e65674d83d7d59ff3c6`; this two-line publication note extends its documentation while preserving the tested implementation and assertions. Hosted evidence must identify the published source.

## DispatchClaimed codec authorized 2026-11-16

Proto approved nine files and up to 300 added lines for kind 4/producer 2 through the unchanged shared envelope. `src/audit/dispatch_claimed.odin` encodes 120 payload bytes, 176 body bytes and a 208-byte complete event. It adds a distinct 16-byte AttemptId and reuses CapabilityId, EventRef and the existing fingerprint API's [32]u8 representation. No separate fingerprint type or serialization is introduced; only the event digest and linked head are computed here.

Both codec directions require nonzero identities, explicit expected store/epoch, positive task version and an authorization reference strictly earlier than the claim's own sequence. This is the same detectable self/forward-reference rule used for AuthorizationRecorded. Invalid identities/scope return InvalidIdentity; self/forward references and zero task version return Malformed. Control revision zero, all-zero fingerprint bytes and every u64 claim-time value remain intentionally representable. The codec reads no clock and imposes no timestamp ordering or lifetime rule.

Authorization existence and permit status, capability binding/consumption, current task/control versions, fingerprint agreement, producer authenticity and live expiry remain later reference/state/authorization checks. A canonical claim or matching hash supplies no proof of dispatch or successful execution.

Independent Python struct/hashlib/OpenSSL construction first recomputed the approval-0 proposal fingerprint and linked head, then the permit digest/head. It verified that the permit references that proposal, and used the permit's own sequence-3 Ref, capability ID and control revision plus one for the sequence-4 claim. Attempt bytes 0xaa and capability bytes 0x88 differ; claim time `0x0002030405060708` and recorded time `0x0003040506070809` differ and exercise multi-byte encoding. The example claim time is after permit recording and before its expiry. This is an encoding example, not an accepted history. Control revision zero is tested separately as representation only.

Two focused tests cover golden bytes/digest/head and round-trip, reference sequence minus one acceptance, zero task/control cases, opaque fingerprint/claim-time representation, zero/wrong reference store, wrong epoch, zero/self/forward reference sequence, empty attempt/capability, payload length and cross-kind rejection in both directions, plus producer 1 on kind 4. Shared header failures remain covered by the unchanged earlier event tests. The manifest declares five packages/thirty-two tests.

Evidence is retained under `.local/dispatch-codec-review/`: independent recipe/output/hash, source/compiler snapshots and hashes, exact command, exit code, output and fresh JSON reports. The first combined audit build passed all eight named tests without a compile/test failure. Broader validation passed thirteen custody and six event-identity tests, all 28 Python governance controls, inventory, reproduction, documentation and whitespace checks. The five untouched foundation/negative tests were outside this local run. Commands and exits are in validation-results.json. These are native macOS functional results; hosted/Linux and operational dispatch verification remain separate.

On 2026-11-17 the owner authorized DispatchClaimed publication through a PR after all hosted checks pass. The local evidence archive has SHA-256 `f64ed7afa08a8f2dea49280e98c24c04c5293d0c2c378c512151234165ef6651`; this two-line publication note extends its documentation while preserving its tested implementation and assertions. Hosted evidence must identify the published source.

## ObservationRecorded codec authorized 2026-11-17

Proto approved eight files and up to 300 added lines for kind 5/producer 3, using the unchanged shared envelope and existing EventRef/EvidenceId types. `observation_recorded.odin` encodes 55 payload bytes, 111 body bytes and a 143-byte complete event. Its typed value carries only Returned or Indeterminate outcome; criterion and observed bytes are derived. Returned writes criterion 1 and ASCII NOOP, while Indeterminate writes criterion 1 and four zero bytes. There is no observed-bytes argument.

Decode validates the outcome/criterion and all four observed bytes before returning a typed value, then requires nonzero identities and explicit expected store/epoch. Unsupported outcome/criterion/producer returns Unsupported, inconsistent observed bytes returns Malformed, and invalid identities return InvalidIdentity. Claim sequence must be strictly earlier than the observation, using the same self/forward-reference rule as AuthorizationRecorded and DispatchClaimed. Failures return zero output.

Recorded time has no ordering rule here. Claim existence and confirmation, the claim's attempt/capability identities, observer authenticity, observation uniqueness, actual execution, evaluation and authoritative completion are later checks. Canonical observation bytes and hashes supply no proof that a returned result occurred. This slice computes the event digest and linked head only.

Independent Python struct/hashlib/OpenSSL construction first rebuilt the published claim body from its payload and metadata, recalculated its digest and linked head, and verified the chain to the permit. Both new vectors reference that claim's own sequence-4 Ref and continue its head at sequence 5. Evidence bytes 0xbb differ from the attempt's 0xaa and capability's 0x88. The vectors are alternative encoding examples, never a history containing two observations of one claim.

Two focused tests cover both golden bytes/digests/heads, round-trip and a representation-only zero recorded-time case; lowercase returned bytes, one wrong byte at each position for both outcomes, NOOP on indeterminate, outcome 0/3, criterion 0/2, zero evidence/claim store, wrong claim store/epoch, zero/self/forward sequence, wrong payload length, cross-kind input in both directions and producer 2 on kind 5. The sequence-minus-one boundary is accepted by the golden cases. Existing codecs, helpers and tests remain unchanged. The manifest declares five packages/thirty-four tests.

Evidence is retained under `.local/observation-codec-review/`: independent recipe/output/hash, source/compiler snapshots and hashes, exact command, exit code, raw output and fresh JSON reports. The first combined audit run passed all ten named tests without a compile/test failure. Broader validation passed thirteen custody and six event-identity tests, all 28 Python governance controls, inventory, reproduction, documentation and whitespace checks. The five untouched foundation/negative tests were outside this local run. Commands and exits are in validation-results.json. These are native macOS functional results; hosted/Linux and operational observer verification remain separate.

## EvaluationRecorded and TransitionAccepted codecs authorized 2026-11-17

Proto approved a paired pure codec increment of eleven files and up to 550 added lines. Kind 6 uses producer 4 and carries 115 payload bytes in a 203-byte event. Kind 7 uses producer 5 and carries 105 payload bytes in a 193-byte event. Both use the existing envelope, SHA-256 event domain and link calculation. The two codecs share helpers for encoding and reading a 32-byte Ref and checking the supplied reference chain.

Both codecs require nonzero IDs and references in the expected store and epoch. They check sequence order as claim < observation < evaluation or claim < evaluation < transition. Gaps are valid. Evaluation represents criterion 1 and validates verdict 1 (verified) or 2 (rejected). The supplied observation digest is opaque to the codec. Transition derives the complete state byte (2) and the next task version. It checks the expected version before adding one and validates the encoded result on decode. Expected control revision is recorded verbatim. Current-state comparisons, the control revision increment, observation digest verification, same-claim lookup, uniqueness and capability checks belong to runtime evaluation and the acceptance transaction.

Independent Python field-table construction and OpenSSL digest checks preceded implementation. The two alternative sequence-6 examples recompute observation bytes, digest and linked head from the published observation payloads and shared claim head. Returned leads to verified, then to a sequence-7 complete transition. Indeterminate leads to rejected and ends there. The transition retains the claim's expected task version and includes the control advance for consumption. These examples exercise representation; live outcome verification requires the registered evaluator and acceptance boundary.

Four focused tests check exact encoding, decoding, digests and linked heads plus typed rejection of invalid scope/order, identifiers, producer and payload fields. The task-version test exercises both the last valid increment and overflow. Native macOS verification passed all 14 audit tests, all 28 governance controls, documentation governance and vector reproduction. The review recipe, vectors, command output and JSON reports are retained under `.local/evaluation-transition/`.

## CapabilityRevoked and AttemptDisposition authorized 2026-11-17

Proto approved this pair of pure codecs within ten files and 400 added lines. CapabilityRevoked (kind 9, producer 2) encodes a 58-byte payload in 146 event bytes. AttemptDisposition (kind 10, producer 5) encodes a 43-byte payload in 131 event bytes. The claim reference identifies the attempt for subsequent lookup. Both codecs reuse the shared envelope, reference and digest operations. Encode and decode require an earlier, nonzero reference in the supplied store and epoch. A capability ID must be nonzero. Control revision zero is valid. Both codecs accept reasons 1–13 across their supported representations; disposition accepts 1 or 2.

The independent Python field-table recipe checked predecessor bodies, digests and linked heads against the published vectors before constructing new bytes. OpenSSL cross-checked each SHA-256 calculation. The revocation example branches from the sequence-3 permit using its capability ID and expected control revision plus one. The two terminal examples branch independently from the sequence-4 claim. One records indeterminate and the other reject-stop. The vectors demonstrate encoding; checking actual grant state, matching a capability to its grant, checking for an unterminated claim, resolving references and deciding the applicable reason belong to later runtime/store verification.

Four focused tests cover the complete bytes, digest, linked head and round-trip of each example, zero control revision, reason boundaries, identity and order errors, unknown disposition, invalid capability and cross-kind input. Local validation uses the pinned macOS compiler. The recipe, logs and named test report are retained in `.local/increment-a/`. Kind 8 has a separately approved review scope.

## RejectionRecorded codec authorized 2026-11-17

The owner authorized Increment B within eight files and 350 added lines. Kind 8 uses the existing envelope and an owned optional EventRef. A zero tag selects 124 event bytes (36-byte payload); tag 1 selects 156 (68-byte payload). Encoding leaves unused capacity zero. Event hashing covers the used 92- or 124-byte body. The decoder checks total size before reading producer, uses the shared envelope to validate kind, version and declared payload size, then independently validates producer range and stage compatibility through the seven permitted assignments.

The approved interpretation of the producer-role rule assigns stages 1–7 respectively to producers 1, 2, 2, 3, 4, 5, 5. Both codec paths accept only registered reasons 1–13. A present related reference must be nonzero, match the expected store/epoch and precede the containing event. Tag/length disagreement or a tag outside 0–1 is malformed. Runtime semantics, producer authentication, historical reference closure and exactly-once receipt import require later verification.

Independent Python construction with OpenSSL digest checks preceded implementation. One encoding example records approval unavailable against the related proposal. The other uses producer 5, stage 7, reason 13 and an absent reference: its rejected-input digest is SHA-256 over the entire published 203-byte custody REJECTION frame, including its final record hash. The two examples are alternative event bytes. A named assignment table exercises all seven producer/stage pairs. Focused rejection cases cover role mismatch, unknown producer, invalid stage/reason, crossed tags/lengths, tag 2 and invalid related references.

## Single-epoch custody history validation authorized 2026-11-17

Proto approved six files and up to 250 added lines for the first pure slice 3a increment. The validator takes a supplied byte sequence, expected store and decoded published head. Starting from ordinal 1 and a zero predecessor hash, it uses the existing record decoder to validate frame bytes and linkage. GENESIS establishes the epoch-1 checkpoint. PENDING must extend the committed checkpoint with one eligible pledge. COMMITTED must match that entire live pledge. A matching published head includes both the checkpoint and its custody record hash. The returned view retains the pending pledge, latest committed head, custody ordinal and record hash.

A published head matching an older validated checkpoint yields HeadPublicationPending. An unexplained published head or invalid history yields AttestationHistoryFault. An incomplete final byte prefix yields TornFinalRecord only when the preceding complete history explains the supplied head. These outcomes classify supplied evidence; physical finality, journal reconciliation, resource enforcement, durable repair and readiness belong to later slices. EPOCH and REJECTION histories remain outside this first validator. The existing effect qualification and entry gates continue to apply.

The focused test uses an enrolled three-frame chain with independently reproduced final custody hash `cf70871bc3142a9c387b900193db9c44a33894c5f1b5fcbfe065adca3530fc46`. It checks pending and committed states, stale and contradictory heads, both outcomes of an incomplete commit, and individually well-formed frames with a changed predecessor or a conflicting pledge. This closes a cross-frame coverage gap in the existing single-record tests.

## Pure custodian requests and peer roles authorized 2026-11-17

Proto approved up to eleven files and 450 added lines for the five WBCR v1 requests, their request digest and the pure endpoint/peer decision. The fixed 11-byte header carries magic, version, operation and little-endian payload size. The bounded encoder returns used length and storage for the largest specified request (11 + 1186 bytes). Digest input includes the NUL-terminated request domain and the complete used request. Prepare/confirm delegate to the pledge codec. Verify carries store, epoch and an opaque receipt cursor; validation compares the supplied expected scope. The service will check the cursor against the custody tip.

Enroll and epoch-change request types expose only the authorization payload. Encoding reuses the corresponding history encoder and excludes its final eight UID bytes. Decoding checks the declared size, pads a bounded local buffer with eight zeros to use the existing history decoder, and takes only the request fields from its result. That internal padding carries no credential information. The counted reason enforces the exact administrative request shape. Enrollment's epoch field is fixed at 1. Enrollment eligibility and operator UID acquisition belong to the effectful boundary.

The peer decision takes resolved listener identities, configured UIDs, an optional observed UID and the operation. The runtime listener permits operations 1–3 for the configured runtime UID. The separate administrative listener permits operations 4–5 for an allowlisted operator. Missing credentials, unknown endpoint or operation, overlapping listeners, and a runtime UID anywhere in the operator list yield Denied. Startup must resolve the actual listeners; slice 3b must obtain credentials from the connected socket and enforce the operator check at the write boundary.

Independent Python/OpenSSL construction framed the published payloads and checked all five request digests before implementation. Two codec tests cover exact bytes, digests, round-trip, header and scope failures, and UID-suffixed enrollment/epoch data with a matching declared length. A table-driven peer test exercises all permitted operations and distinct denial paths. Local evidence and reproduction commands are in `.local/wbcr/`. WBRS disclosure rules, actual OS access denial and durable denial recording retain their own gates.

## WBRS replies and disclosure authorized 2026-11-17

Proto approved a pure WBRS codec within ten files and 450 added lines. The 13-byte header and 138-byte base payload permit exactly 151, 287, 354 or 490 bytes depending on the pending tuple and embedded REJECTION tags. The decoder checks total size before indexing, validates both tags against that size and compares the operation and request digest with caller-supplied expectations. Encoding uses a zero-initialized 490-byte buffer and explicit used length. The status registry spans 0–19.

Authentication comes from the caller. For an unauthenticated denial, the encoder clears the committed Ref/head, omits both optional fields and writes tip zero. Decode rejects a nonzero tip or any other protected field in that context. This owner ruling closes an activity-counter disclosure. Authenticated replies carry the supplied real tip, including when no receipt frame is returned. The 32-byte receipt field can carry the denied caller's own durable receipt hash. CHECKPOINT_STORAGE_FAULT requires a zero receipt. The codec cannot determine whether a receipt was durably recorded.

Only a successful authenticated Verify may carry a complete 203-byte REJECTION frame. Its ordinal must exceed the supplied cursor and be at most the returned tip. A successful verify also rejects a cursor beyond the tip when the embedded frame is absent. The existing frame decoder validates the record bytes and checksum against the expected store. Its ordinal, predecessor and receipt epoch are taken from the embedded frame for structural checking; trusted history must establish their provenance and choose the earliest eligible receipt. Pending tuples pass through the existing pledge codec. The expected epoch in the context identifies the committed reply scope.

Independent Python field-table construction and OpenSSL request-digest checks preceded implementation. Six examples cover the four shapes and the caller's durable denial versus nondurable storage fault. Three focused tests cover exact vectors, zero tails, typed round-trips, header/tag/size errors, disclosure, request-digest binding, the cursor interval and embedded-frame corruption. These examples demonstrate wire semantics; socket authentication, receipt selection and persistence are later boundaries. The first compile failed on the reserved Odin keyword `context`; renaming the parameter to `ctx` allowed the custody package to pass. Local reproduction and verification records are in `.local/wbrs/`.

## Multi-epoch history validation authorized 2026-11-17

Proto approved seven files and up to 350 added lines for extending the pure validator to EPOCH and REJECTION records. Before enrollment, an absent published head and a valid denial-only prefix yield Unenrolled. GENESIS establishes epoch 1 even after denials. Once enrolled, a missing published head yields CheckpointInconsistent on a valid complete history. REJECTION frames must match the active epoch (zero before enrollment). They advance the custody ordinal and record hash independently of the event checkpoint and pending pledge.

EPOCH validation compares the complete old checkpoint and the exact unresolved pending frame hash (zero when absent). The epoch codec checks advancement, sequence zero and the new head. The validator adopts the checked checkpoint, preserves the old evidence in the supplied history and starts the new segment with no live pledge. A local map retains each GENESIS/EPOCH authorization ID throughout the scan; a duplicate durable administrative record is a fault, and allocation failure withholds a usable view. The caller owns allocation policy, clock/scan limits and the decision to perform any physical recovery action.

The focused test starts with an epoch-zero denial and checks delayed genesis, denial interleaved with a pledge, two epoch advances and a new-epoch commit. Re-encoded alternatives cover repeated genesis, wrong denial epoch, conflicting old checkpoint, wrong pending hash, and reuse of enrollment and epoch authorization IDs. Prior single-epoch checks remain in the custody package.

## Context

The foundation has local Linux x64 and macOS ARM64 evidence. It does not yet execute proposals, consume capabilities, verify external observations, commit runtime facts, or replay an authoritative event store.

The next boundary must answer: how can Warband prove that an action used the correct authority, generated trustworthy evidence, and produced at most one valid authoritative transition across failures and restarts?

The constitution remains authoritative. This draft proposes mechanisms beneath it; it does not weaken the contracts or claim unimplemented guarantees.

## Owner-selected storage and custody direction

On 2026-10-18, Proto selected **Option 1: same VM, separate checkpoint custodian**. The selected design direction uses SQLite for the single event store and a separate local custodian process under a distinct OS identity for the trusted checkpoint. The custodian owns its checkpoint storage; the runtime has no direct write access to that storage. Both audit and authoritative projections still derive from the single event history. Checkpoint metadata is not another authoritative event ledger.

The intended protection is detection of alteration, truncation or replacement of checkpoint-covered history by an attacker who can rewrite the journal but cannot control the custodian or its protected storage. The design trusts the VM kernel and administrator. It does not establish detection when an attacker controls both custody domains, compromises guest root, or rolls back the entire VM including the custodian. A separate filename or directory under the runtime's own writable identity does not meet this direction.

Checkpoint custody does not validate the truth of producer observations or authorize state changes. A compromised runtime must not gain an unrestricted checkpoint replacement or reset operation. The protocol direction below uses local peer credentials and a separate operator path; exact wire formats, enrollment and implementation verification remain open. No host-side or remote custodian is selected.

The exact SQLite version, dependency provenance, transaction and synchronization settings, checkpoint persistence mechanism, filesystem assumptions and journal/head crash-state table still require review. This selection is not formal acceptance of ADR-0005, implementation authorization, production architecture selection or verified security evidence.

## Proposed scope and guarantees

Begin with one runtime writer and one deterministic no-op action. Use one durable append-only event history to derive audit and authoritative projections, preserving ADR-0002 and ADR-0003. Derived indexes/caches are reconstructible and never independently authoritative.

The internal acceptance boundary can provide at-most-once committed transitions through atomic expected-version and uniqueness checks. Successful recovery can restore a committed result. Exactly-once external execution is not promised: execution and local persistence cannot generally share an atomic transaction. Unknown side effects remain unknown until independently reconciled. Availability and automatic progress may be sacrificed for safety.

No provider, arbitrary shell, filesystem write tool, broad network adapter, general orchestration, learned promotion, or distributed consensus is introduced by this proposal. Linux worker isolation and future tool contracts need their own review before powerful tools are added. A no-op test is not sandbox proof.

## Proposed canonical event envelope

Use a versioned deterministic binary encoding with a distinct runtime format, not the 25-byte Phase 1 fixture. The amendment below specifies the v1 widths/order and kind-specific payload registry for operator review before implementation.

Proposed envelope fields, in this order:

| Field | Representation and rule |
|---|---|
| Format marker and schema | Fixed runtime marker and explicit schema version; unknown versions rejected |
| Store identity | Fixed-width identity separating histories and identifier namespaces |
| Custody epoch | Explicit epoch identity binding this history segment to its checkpoint authority; stale-epoch requests rejected |
| Audit sequence | Unsigned fixed-width integer; strict monotonic order, no reuse/wrap |
| Event identity | Full `(store, epoch, sequence)` tuple, represented as a distinct domain type |
| Kind | Registered enum with a schema-defined payload; unknown kind rejected |
| Recorded timestamp | Fixed-width integer under an explicitly defined epoch/unit; no native struct layout |
| Task/run/proposal/attempt references | Distinct identifiers with explicit presence encoding and required bindings per kind |
| Producer identity and version | Registered runtime producer, not supplied as authority by the model |
| Payload length and bytes | Bounded, schema-specific canonical encoding; no generic arbitrary map order |
| Previous event hash | Fixed-width hash linking the immediately preceding event |

The proposed link calculation has two domain-separated stages: an event digest over the canonical envelope fields other than the previous-head field, followed by a head hash binding that digest to the custody epoch, store identity, sequence and previous head. The previous head is bound by the link stage, not silently omitted from integrity coverage. The custodian independently recomputes the link from supplied digest and binding fields. The runtime verifies the supplied digest against the exact persisted canonical event. Exact encodings, domain separators and independent vectors are specified in the amendment below. The runtime supplies ordering, identities and producer metadata; a model-supplied hash or verification flag is never authority. Custodian link checking detects inconsistent calculations, not fabricated content from a compromised authorized runtime.

The amendment selects fixed-width little-endian integers, bounded exact UTF-8 without normalization, SHA-256 and explicit v1 payloads; these are candidate decisions awaiting operator acceptance. Reject malformed, ambiguous, duplicate-field, oversized, unknown, or noncanonical representations. A payload codec registry and independent golden vectors are acceptance prerequisites; no implementation may guess omitted fields.

Proposal fingerprints use a separate domain/schema from event hashes. Bind the normalized tool, arguments, target, expected effect, task/run, policy version, approval requirements, and recovery disposition. The runtime owns allowed effect criteria; a proposal cannot weaken its own success test.

## Integrity and trusted heads

A hash chain alone cannot detect deletion of a valid suffix or a complete rewrite when the attacker also supplies the expected head. Verification needs an independently trusted store identity, sequence, and hash checkpoint covering the history being trusted.

Under the owner-selected direction above, the protected-head interface belongs to the separate same-VM custodian. Its access controls and advancement protocol keep custody outside the defined journal-rewrite attacker's control under the stated assumptions. Checkpoints and their attestation history are integrity metadata, not a second event ledger. No automatic remote anchoring service is authorized.

The trusted head covers every security event acknowledged as durable before dispatch or publication. The selected protocol direction is pledge before SQLite commit, then confirm before acknowledgment. A valid chain with no custodian pledge does not establish tail provenance and is never automatically re-attested. If local commit succeeds but confirmation is uncertain, withhold dispatch/publication and follow the recovery table. Do not report that committed bytes were rolled back.

On 2026-10-18 the owner directed preparation of this revised prepare/confirm design and selected operator reconciliation, with no automatic cancellation, for a durable pledge without its SQLite event. The following is a review specification, not implemented or fault-tested behavior. The event-integrity contract's four viewpoints must be aligned before acceptance. No guarantee against an attacker controlling both journal and checkpoint custody is claimed.

### Custodian operations and identities

Use per-event attestation and at most one outstanding PENDING pledge per store. Each normal operation binds the epoch, store identity, predecessor sequence/head, new sequence/head and event digest. Require exactly the next sequence for this per-event profile; overflow fails closed. Compare and append are serialized within the custodian.

| Operation | Required behavior |
|---|---|
| `prepare` | Authenticate the runtime; match the current epoch/store and committed predecessor; recompute the proposed link; durably append PENDING before replying. An exact replay of the outstanding pledge returns its existing receipt. A different request cannot replace a pending pledge. |
| `confirm` | Authenticate the runtime and match the entire pending tuple. Append and fsync COMMITTED, publish the head durably, then return success. An exact replay of the latest committed tuple returns its original success only after head publication/recovery is complete; it creates no new record. Other predecessor or tuple mismatches never overwrite state. |
| `verify` | Return the epoch, store identity, committed sequence/head, any pending tuple and current fault/readiness state from validated custodian metadata. A committed history record awaiting head publication is not reported as ready. |
| `epoch_change` | Authenticate a separately authorized local operator; bind the exact old epoch/head, proposed new epoch/sequence/head, reason and authorization identity. Preserve the old history and any unresolved pledge. No runtime-accessible reset or automatic cancellation exists. The amendment specifies candidate transition and enrollment formats for owner review. |

The old single-step `advance` operation is replaced by prepare/confirm; retaining a bypass would defeat the pledge. Lost prepare and confirm replies are handled by exact replay. Arbitrary older requests, stale epochs and changed tuples are rejected, not treated as idempotent success.

Linux uses connected Unix stream sockets with `SO_PEERCRED`. Authenticate the runtime UID against an explicit allowlist and have the runtime verify the custodian identity. Use a distinct administrative endpoint with an operator UID allowlist excluding the runtime UID. Root is trusted under Option 1. The operation model is transport-independent, but this authentication profile is local-socket-specific; peer identity does not prove executable integrity or honest observations.

Custodian storage is owned by its separate identity and inaccessible to runtime writes. The socket path and storage paths need protected parents, reviewed ownership/modes/ACLs, no untrusted group-writable parents, and no path substitution through symlinks. Required future verification includes actual denied access under the runtime identity, not metadata inspection alone. No such permission evidence exists yet.

### Durable custody records and publication

The append-only custodian history is the recovery source for checkpoint metadata; the current head file is its materialized committed head. Each bounded frame includes its type, epoch/store, full request tuple, previous custody-record hash, length and checksum. PENDING and COMMITTED frames are distinct. Epoch transitions retain their authorization metadata. Option A below specifies a REJECTION metadata frame selected by Proto on 2026-10-21; it does not change the event head or pledge. Hash chaining detects mid-file edits relative to retained trusted records; it does not survive an attacker controlling custodian storage.

For prepare, append the complete PENDING frame and fsync history before replying. For confirm, append the corresponding COMMITTED frame and fsync history first. Then create a new head file exclusively inside the custodian directory, write it completely, fsync it, rename it over the old head on the same filesystem and fsync the directory. Return success only after all required steps complete. Initial creation also requires durable directory entries. Check every write, short write and synchronization result. Head rename and history append are not one atomic transaction.

On restart, a structurally truncated final frame alone may be removed back to the last complete valid frame, durably, before new writes. Never remove a complete frame with a bad checksum or chain link, an earlier damaged record, or a truncated suffix needed to explain the published head. Those are attestation-history faults. Recover a stale head from complete valid COMMITTED custody records only; never regenerate custody history from SQLite. An unmatched final PENDING remains a live pledge after repair. The amendment defines the candidate frame layout and hash inputs.

### Writer ordering and visibility

The single-writer lock spans preparation, SQLite commit, confirmation and the acknowledgment/dispatch gate. On process death the OS lock is released; the next writer reacquires it and reconstructs the unresolved-work gate from custodian metadata and SQLite before admitting work. A custodian-side pending check also rejects competing pledges. No in-memory flag alone establishes recovery state.

1. Construct the exact canonical event and its bound digest/head from supplied decisions.
2. Durably prepare its pledge with the custodian.
3. Revalidate transaction preconditions and commit that exact event to SQLite. A failed commit leaves its pledge unresolved; it does not silently release the gate.
4. Read/validate the committed event against the pledge and confirm with the custodian.
5. After durable confirmation, apply the acknowledgment/dispatch gate before releasing the writer lock or admitting another mutation.

Reads expose only checkpoint-confirmed authoritative projections. Diagnostic reads may label pending records explicitly, but cannot present committed-but-unconfirmed events as completion. Normal reads must also respect an active integrity fault. A durable dispatch claim is permission to attempt execution, not evidence it occurred: recovery of a confirmed claim alone never automatically redispatches uncertain work.

The proposed Linux SQLite profile is WAL with `synchronous=FULL`, explicitly set and queried on every writing connection. Exact SQLite pin, local filesystem/VFS and VM disk flush assumptions remain review inputs. SQLite durability and custody durability are distinct requirements. macOS development, including any `fullfsync` and `checkpoint_fullfsync` settings, carries no power-loss durability claim; Linux evidence cannot be inferred from a native macOS pass.

### Crash and integrity recovery table

Automatic means only the specified metadata reconciliation or exact confirmation; it does not authorize execution, retry, completion or policy reinterpretation. Validate store identity/epoch and the checkpoint-covered event prefix before applying any row. Multiple faults retain all applicable diagnostics; an identity/integrity fault overrides a more permissive recovery row.

| Crash point or observation | Named state | Recovery | Required disposition |
|---|---|---|---|
| Before any durable PENDING; SQLite equals confirmed head | `READY` | Automatic | No new event was authorized by custody; admit work through normal gates. |
| After durable prepare, before SQLite commit; pending event absent | `PENDING_EVENT_MISSING` | Operator-only | Preserve pledge and stop new work. Owner selected no automatic cancellation. |
| After SQLite commit, before confirm; exact pending event present | `PENDING_CONFIRMATION` | Automatic | Recompute event digest/link from SQLite; match the full pledge, sequence and prefix; resume exact confirm. Withhold acknowledgment/dispatch until ready. |
| After complete durable COMMITTED append, before head publication | `HEAD_PUBLICATION_PENDING` | Automatic | Custodian publishes the head from its validated history, then runtime verifies SQLite matches. No success before publication. |
| After head rename but before directory fsync or confirm reply | `ATTESTATION_UNCERTAIN` | Automatic if records validate | Custodian validates history/head and completes durable publication; exact confirm replay returns its original receipt. Otherwise use the applicable fault below. |
| After durable head publication, before acknowledgment | `CONFIRMED_RESPONSE_PENDING` | Automatic | Return the recorded result after comparison, without adding a fact. A confirmed dispatch claim alone does not prove whether dispatch already happened. |
| Only a truncated final custody frame; remaining history explains head | `TORN_FINAL_RECORD` | Automatic | Remove only the incomplete final frame durably, recover the resulting READY/PENDING/COMMITTED state and apply its row. |
| SQLite ahead with no exact pledge, including an extra suffix beyond it | `UNATTESTED_TAIL` | Operator-only | Preserve evidence; no chain-only re-attestation, truncation or automatic repair. |
| SQLite behind confirmed history, checkpoint hash differs, or pending event differs | `INTEGRITY_FAULT` | Operator-only | Block mutation/dispatch/trusted completion; investigate. Epoch change requires separate operator authorization. |
| Custody history valid but head malformed, stale or missing with a recorded genesis | `CHECKPOINT_INCONSISTENT` | Automatic only if uniquely reconstructible | Rebuild head from custody history; do not reconstruct history from the event store. A contradictory valid head is an integrity fault. |
| Complete bad frame, broken custody hash link, interior corruption or unexplained published head | `ATTESTATION_HISTORY_FAULT` | Operator-only | Preserve damaged files; no speculative history repair or reset. |
| Store exists without trusted custody history/checkpoint and no authorized genesis | `CHECKPOINT_MISSING` | Operator-only | No automatic enrollment from existing SQLite contents. |
| Store identity differs or epoch is unsupported/stale | `STORE_IDENTITY_MISMATCH` / `EPOCH_MISMATCH` | Operator-only for persisted mismatch | Reject requests without mutation; investigate persisted disagreement. Do not relabel a store. |
| Custodian unreachable or request outcome unknown | `ATTESTATION_UNCERTAIN` | Automatic exact replay after recovery | Block protected progress; no timeout-based assumption that a write failed. |
| Disk full, write error or fsync failure | `CHECKPOINT_STORAGE_FAULT` | Operator-only before resumption | No success; preserve current files and pending state. Restore storage health, then reconcile actual records. |
| Peer outside the operation's UID allowlist | `CUSTODIAN_AUTH_FAULT` | Terminal for request | Reject without checkpoint/pledge mutation; selected Option A records denial metadata only; no fallback authentication. |
| Different predecessor/request conflicts with committed or pending tuple | `CHECKPOINT_CONFLICT` | Terminal for request; operator review if persisted divergence | No overwrite. Exact latest committed replay is the narrowly defined exception, not a conflict. |
| Unsafe custody ownership, permissions, ACLs or parent path | `CUSTODY_BOUNDARY_FAULT` | Operator-only | Refuse startup or further protected operations until boundary is restored and reviewed. |

An operator recovery action records a disposition; it is not evidence that missing work succeeded. No epoch change suppresses the original fault or creates an authoritative completion. Operator acceptance of the amendment remains required before implementation.

## Authority and evidence

Every authoritative transition kind, including control-state changes, needs recorded runtime-produced evidence and a producing event. The state boundary is the only writer; coordinator, model, tool, and evaluator outputs remain inputs.

Before execution, bind authorization to normalized proposal digest, exact action/target, task/run, attempt, policy epoch, expected task version, required approval, lease expiry/use limit, and predefined recovery disposition. Approval-required actions remain rejected until approval provenance/binding is implemented.

Capability issuance and consumption use the runtime registry. Caller-provided IDs alone cannot grant authority. Persist one consumption claim per lease/use and one dispatch attempt per claim. Verify approval/policy freshness, current state, expiry, revocation, and all bindings at claim time. Reject wrong scope, replay, or changed payload.

A trusted observer records bounded outcomes against the persisted attempt identity. An independent evaluator checks runtime-owned criteria and references registered producer identity, observation digest, covered criteria, and producing events. Executor/model assertions of success do not substitute for an observation. Reject evidence from another task/run/attempt, substituted content, unknown producers, or missing criteria. Secret-bearing data requires a reviewed redaction/evidence policy before a tool exposing it is added.

## Proposed transaction boundaries

All persisted control and task state is derived from the same event history. Distinguish audit sequence, task state version, capability consumption identity, attempt identity, and transition identity; they are not interchangeable counters.

| Boundary | Atomic local work | Gate after durable recording |
|---|---|---|
| Authorization | Append proposal normalization result, explicit policy/recovery decision, required approval binding and capability grant evidence | No dispatch from an unrecorded or untrusted authorization |
| Dispatch claim | Validate expected state/policy/approval/lease; atomically consume permitted use and append one attempt claim with authorization receipt | Dispatch only after the claim is durable and covered by the trusted head |
| Observation | Append trusted observer result or explicit unknown-outcome record, bound to the attempt | Evaluation only uses recorded observations |
| Evaluation | Append evaluator identity/result/coverage and evidence references | Evaluation alone cannot mutate task state |
| Acceptance | Revalidate bindings/current task version/evidence; append one accepted transition fact under unique transition/attempt constraints | Publish authoritative completion only through the state boundary and required integrity gate |

The storage adapter executes transactions requested by the domain plan; it does not invent policy. Expected-version and unique-identity checks must be in the same local transaction as acceptance. Concurrent acceptors cannot both commit against the same eligible version. If a duplicate already committed, return its recorded result without creating a new fact or re-executing the action.

Separate task and control-state version rules must define which claim/authorization events advance each projection. A result must target the version owned by its persisted claim, not an accidentally stale pre-claim version. Task creation, grant, consumption, completion, and recovery require an explicit transition/evidence registry before coding. There is no direct fact-insertion API.

SQLite is the owner-selected direction for the first local transactional store. Its exact dependency profile, durability, constraints, locking, checkpoint integration, migrations and power-loss assumptions require review before implementation. Do not add a second authoritative database or rewrite prior accepted ADRs to justify storage shortcuts.

## Recovery dispositions

| Last proven boundary | Required behavior |
|---|---|
| No durable dispatch claim | No action permitted; reevaluate only through the normal authorization gate |
| Durable claim, no proven outcome | Mark indeterminate; do not automatically redispatch the consumed lease |
| Proven observation, no evaluation | Reevaluate recorded evidence deterministically; do not rerun the tool |
| Proven evaluation, no acceptance | Revalidate the current version and attempt bindings; commit once or record rejection |
| Accepted fact, caller missed response | Return the stored result; no second transition or execution |
| Integrity or storage failure | Stop mutation/dispatch/publication; surface the failure and reconcile before trusting replay |

Retry requires recorded evidence proving it is safe plus a new allowed attempt/lease. A timeout, lost worker response, or crash is not proof no side effect occurred. Recovery dispositions are typed: reconcile, compensate, request approval, or reject/stop. Compensation is a separately authorized and verified action; it may not erase residual effects. Never call uncertain work complete.

## Deterministic replay

Replay validates schema, ordering, hashes, trusted head, identifier uniqueness and reference closure before constructing authoritative state. Apply only eligible accepted facts through pure transition rules; raw claims, failed attempts and rejected results remain audit-only for task completion.

Replay performs no model call, tool execution, capability reissue, retry, compensation, live clock lookup, or reinterpretation under today's policy. Recorded identities, versions, policy/evaluator decisions and criteria form the historical input. A schema migration needs a reviewed explicit procedure; unsupported history blocks trust instead of being silently skipped.

## Proposed verification matrix

These are required future proofs, not passing Phase 1 tests.

| Concern | Required proof | Existing requirements |
|---|---|---|
| Authority and proposal isolation | Direct/forged fact insertion rejected; parser/model paths cannot access state writer | WB-CON-001/002; WB-INV-001/009 |
| Canonical encoding | Independent cross-platform golden vectors, hash vectors, malformed/unknown/ambiguous input rejection | WB-CON-007/008; WB-NEG-001/012 |
| Capability/approval | Scope, expiry, revocation, reuse, policy/state drift and payload mutation rejected | WB-CON-004/005/009; WB-INV-002/003/004/007; WB-NEG-003/004/008/010 |
| Evidence provenance | Fabricated success, unknown producer, substituted/cross-run evidence and incomplete criteria rejected | WB-CON-003/006; WB-INV-005/009; WB-NEG-007 |
| Atomic acceptance | Duplicate/stale/out-of-order delivery and concurrent acceptors cannot create another valid fact | WB-CON-006/008; WB-INV-008; WB-NEG-005/006 |
| Audit/integrity | Alteration, reorder, truncation, rollback, whole-history replacement and head conflict detected within reviewed assumptions | WB-CON-007/008; WB-INV-006; WB-NEG-009 |
| Crash recovery | Inject failure before/after each durable boundary; never redispatch uncertain execution or acknowledge unproven completion | WB-CON-006/008/009; WB-INV-004/005/008 |
| Replay | Mixed accepted/rejected history produces identical state without I/O or live-policy/time reinterpretation | WB-CON-001/006/008; WB-INV-009 |

Learning/promotion remains unsupported under WB-INV-010. Provider independence WB-CON-010 is preserved by deterministic/adversarial proposal fixtures, not a real provider integration.

## Compatibility migration and review gates

There is no runtime event history to migrate. Preserve the Phase 1 fixture format and its tests as independent foundation data; do not reinterpret its bytes as events. A runtime format receives its own schema and domain identifiers.

Before acceptance, freeze the complete wire/payload and transition registries; complete review of storage durability and the selected same-VM checkpoint custody; resolve journal/head crash windows and task/control version rules; define the observer/evaluator trust boundary; and reconcile procedure-layering/effect dispatch without placing I/O in pure domain rules. Proto is assigned as decision owner. High orchestration, pure decisions and technical adapters must be reviewed against repository guidance; no exception is silently accepted here.

On acceptance, align authoritative-state, model-proposal, independent-evaluation and event-integrity contracts, security/trust/threat documents, execution pipeline, package/dependency ownership, negative paths and traceability. Preserve existing identifiers; add new cases for newly specified failures. Authorize Phase 2 implementation separately, beginning with the deterministic no-op and the required rejection/crash/replay proofs.


## Amendment: resolved Phase 2 decision candidate

This amendment is a design specification, not implementation or ADR acceptance. The operator requested these decisions and separate review PRs. Existing unresolved fields are visible in the [reviewed baseline, lines 39–63](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/decisions/0005-event-integrity-acceptance-and-recovery.md#L39-L63); the fixed custody direction and fault dispositions are retained above. The Phase 2 entry requirements remain in [the phase plan, lines 100–107](https://github.com/progentic/Warband/blob/3cbfd55b9157058cbd72dfcc6e14a59080925681/docs/governance/PHASE_PLAN.md#L100-L107).

### 1. Event identity

**Decision:** Event identity and every event reference are `(store_id, epoch, sequence)`. Store IDs are 16 opaque bytes, epochs and sequences are unsigned 64-bit integers. Store IDs are nonzero; epochs start at 1, ordinary event sequences at 1. Sequence 0 is the epoch's custody genesis, not an event. Epoch increases exactly by one under operator authorization; sequence may restart at 1 in that new epoch. Overflow is a fault, never wraparound.

Every event primary key, foreign reference, replay index and uniqueness constraint includes all three fields. Task, run, proposal, capability, attempt, evidence, transition, command and authorization IDs are distinct nonzero 16-byte types, scoped to store and epoch; their lookup keys include that scope. An event reference never resolves in an implicit current store/epoch. Cross-epoch task/evidence references are rejected in v1.

**Alternative:** Keep `(store, sequence)` and forbid sequence reuse forever. **Consequence:** Including epoch preserves the selected epoch recovery mechanism without identity collisions; references occupy 32 bytes and require explicit scope checks.

### 2. Canonical binary v1

**Decision:** All integers are unsigned little-endian, with exact widths below. No native struct layout, padding, floats, varints, maps, duplicate fields or trailing bytes. Text is exact well-formed UTF-8 without normalization or NUL, encoded as `u16 byte_count || bytes`, maximum 1024 bytes. Missing text is length zero only when the schema explicitly permits it. Hashes are 32 raw bytes. `Ref` is `store[16] || epoch:u64 || sequence:u64`; `OptionalRef` is tag `u8` (0 absent, 1 followed by Ref); any other tag is invalid. Absent IDs in conditional payload fields are exactly 16 zero bytes; zero is otherwise invalid. Unknown schema, kind, producer, enum or reserved flag fails closed.

| Event body field, in order | Bytes / rule |
|---|---|
| Magic / version / kind | ASCII `WBEV`, u16=1, u16 from registry below |
| Store / epoch / sequence | 16 / u64 / u64; the full event identity |
| Recorded time | u64 microseconds since 1970-01-01T00:00:00Z; runtime observation, never a replay clock |
| Producer / producer version | u16 / u16, exact registry below; version=1 |
| Payload length / payload | u32 / exact kind schema; maximum payload 65536 bytes |

The body header is 56 bytes. An encoded event is `body || previous_head[32]`; total maximum 65624 bytes. All payload schemas concatenate their fields in listed order. No optional references exist except where explicitly stated.

| Kind / producer | Exact payload fields in order |
|---|---|
| 1 TaskCreated / 1 | task ID, run ID, command ID, input SHA-256, inline evidence ID |
| 2 ProposalRecorded / 1 | task ID, run ID, proposal ID, expected task version:u64, policy version:u64, action:u16=1 (NoOp), target:u8=0 (none), argument length:u32=0, criterion:u16=1 (NoOpV1), recovery:u8=1 (stop/reconcile), approval required:u8 (0/1) |
| 3 AuthorizationRecorded / 2 | proposal Ref, expected control revision:u64, decision:u8 (1 permit/2 reject/3 require approval), capability ID, expiry microseconds:u64, use limit:u8, inline evidence ID |
| 4 DispatchClaimed / 2 | authorization Ref, attempt ID, capability ID, expected task version:u64, expected control revision:u64, proposal fingerprint[32], claim time microseconds:u64 |
| 5 ObservationRecorded / 3 | claim Ref, evidence ID, outcome:u8 (1 returned/2 indeterminate), criterion:u16=1, observed bytes[4] (ASCII `NOOP` for returned; four zero bytes for indeterminate) |
| 6 EvaluationRecorded / 4 | observation Ref, claim Ref, observed-event digest[32], criterion:u16=1, verdict:u8 (1 verified/2 rejected), evidence ID |
| 7 TransitionAccepted / 5 | evaluation Ref, claim Ref, transition ID, expected task version:u64, expected control revision:u64, new task version:u64, new state:u8=2 (complete) |
| 8 RejectionRecorded / 1–5 | stage:u8 (1 input/2 authorization/3 claim/4 observation/5 evaluation/6 acceptance/7 recovery), reason:u16 from reason registry, related OptionalRef, rejected-input SHA-256 |
| 9 CapabilityRevoked / 2 | authorization Ref, capability ID, expected control revision:u64, reason:u16 |
| 10 AttemptDisposition / 5 | claim Ref, expected control revision:u64, disposition:u8 (1 indeterminate/2 reject-stop), reason:u16 |

Reason registry: 1 malformed, 2 unsupported, 3 identity mismatch, 4 stale version, 5 expired, 6 revoked, 7 already used, 8 approval unavailable, 9 evidence invalid, 10 outcome uncertain, 11 missing recovery policy, 12 operator revocation, 13 custody request denied (selected Option A). The stage must match the emitting producer's role; arbitrary producer/stage combinations are invalid. Input rejection containing no usable IDs still has its own runtime-owned event identity and input digest; raw rejected input is not persisted. For authorization decision 1, capability ID is nonzero, use limit=1 and expiry must exceed recorded authorization time. Decisions 2/3 use zero capability/expiry/use limit and grant nothing. The Phase 2 deterministic NoOp policy registry has version 1 only; unknown or changed policy versions reject rather than silently reinterpreting history. No approval-required proposal can receive permit in Phase 2; the approval-binding positive path belongs to Phase 3. This is a scoped rejection proof, not a claim of a working human approval flow.

Hash domains below are their exact ASCII bytes including the final zero byte; concatenation is byte concatenation:

- `event_digest = SHA256("warband.event.v1\0" || body)`.
- `new_head = SHA256("warband.link.v1\0" || store[16] || epoch:u64 || sequence:u64 || previous_head[32] || event_digest[32])`.
- `proposal_fingerprint = SHA256("warband.proposal.v1\0" || canonical ProposalRecorded payload)`. The payload binds task/run, expected state, exact no-op shape, policy, criterion, recovery and approval requirement. No proposal-selected criterion weakens NoOpV1.
- `request_digest = SHA256("warband.request.v1\0" || complete request bytes)`.

#### Custody frames, head and request framing

Custody history uses a separate ordinal:u64 starting at 1 and never resetting across epochs. Each frame starts with `WBCH || version:u16=1 || type:u8 || payload_length:u32 || ordinal:u64 || previous_record_hash[32]` (51 bytes), followed by `header_hash[32]`, payload, then `record_hash[32]`. Types are 1 PENDING, 2 COMMITTED, 3 GENESIS, 4 EPOCH, and 5 REJECTION under selected Option A below. The outer format ceilings are 65536 payload bytes and 65651 frame bytes. The five specified v1 kinds have tighter bounds: PENDING/COMMITTED 136 payload bytes, GENESIS 51–1074, EPOCH 171–1194, and REJECTION 88. Their actual supported maximum is therefore 1194 payload bytes plus 115 framing bytes, or 1309 total. The all-kind codec enforces these tighter bounds; the outer ceilings grant no permission to accept larger v1 records. First previous-record hash is zero. Header hash is SHA256 of `"warband.custody.header.v1\0" || first 51 bytes`; record hash is SHA256 of `"warband.custody.record.v1\0" || header including header_hash || payload`. The record hash is also the frame checksum and receipt. A bad complete header/hash/link is corruption, never a truncation repair. A final incomplete header is repairable only if all present fixed fields are consistent; an invalid prefix is a fault. A valid complete header with insufficient final payload/checksum is a truncated final frame, subject to the recovery table's head-consistency rule. No scan-forward resynchronization is allowed.

PENDING/COMMITTED payload is the exact 136-byte tuple: `store[16], epoch:u64, prev_seq:u64, prev_head[32], new_seq:u64, new_head[32], event_digest[32]`. COMMITTED must match the outstanding PENDING, including its epoch. Exact replay returns the original record-hash receipt. A later pending pledge does not invalidate the latest committed request's replay receipt or allow that replay to clear the later pledge.

GENESIS payload is the enrollment payload defined below. EPOCH payload is the epoch-change payload below. A materialized head is `WBHD || version:u16=1 || committed Ref || head[32] || committed_record_hash[32] || checksum[32]`; checksum is SHA256 of `"warband.head.v1\0" || all preceding head-file bytes`. Size is 134 bytes. The GENESIS/EPOCH record supplies sequence 0 until the first event is confirmed.

A socket request is `WBCR || version:u16=1 || operation:u8 || payload_length:u32 || payload`, maximum payload 65536. Operations: 1 prepare and 2 confirm carry the tuple; 3 verify carries store[16]/epoch:u64/after_custody_ordinal:u64 under selected Option A; 4 enroll and 5 epoch_change are administrative only and carry the payloads below. Requests are length-delimited; EOF, excess bytes, unsupported versions and unknown operations reject without checkpoint or pledge mutation; selected Option A records only denial metadata. An application reply is `WBRS || version:u16=1 || operation:u8 || status:u16 || payload_length:u32 || payload`. Its fixed payload is request digest[32], receipt[32] (the durable REJECTION record hash under selected Option A; zero if no durable receipt exists), committed Ref, head[32], pending tag:u8 (0/1), followed by the pending tuple only for tag 1. Under selected Option A, append custody_tip_ordinal:u64 and rejection_present:u8 (0/1), followed by exactly one complete 203-byte REJECTION frame only for tag 1. A successful authenticated verify returns the earliest REJECTION after the supplied cursor through the reported custody tip, or tag 0 if none; this is a single-receipt read, never a batch. Other operations use tag 0. An unauthenticated denial reveals no committed Ref/head or pending tuple (zero/absent fields). Replies never contain raw prompts, paths, authentication secrets, bearer credentials or generic error text; the specified peer metadata is returned only through authenticated verification.

Status registry is 0 READY; 1 PENDING_EVENT_MISSING; 2 PENDING_CONFIRMATION; 3 HEAD_PUBLICATION_PENDING; 4 ATTESTATION_UNCERTAIN; 5 CONFIRMED_RESPONSE_PENDING; 6 TORN_FINAL_RECORD; 7 UNATTESTED_TAIL; 8 INTEGRITY_FAULT; 9 CHECKPOINT_INCONSISTENT; 10 ATTESTATION_HISTORY_FAULT; 11 CHECKPOINT_MISSING; 12 STORE_IDENTITY_MISMATCH; 13 EPOCH_MISMATCH; 14 CHECKPOINT_STORAGE_FAULT; 15 CUSTODIAN_AUTH_FAULT; 16 CHECKPOINT_CONFLICT; 17 CUSTODY_BOUNDARY_FAULT; 18 MALFORMED; 19 UNSUPPORTED. A successful prepare/confirm returns READY for that operation, but prepare does not advance the committed head or clear the runtime pending-work gate. For an unestablished committed head, Ref/head are all zero and only fault/admin replies are valid. Permission is determined by authenticated endpoint identity, never operation bytes alone.

**Migration:** v1 rejects unknown versions rather than attempting another parser. No in-place rewrite of events or custody history. A later migration needs a new reviewed schema/ADR, a verified source snapshot and explicit operator authorization, retaining original bytes and full event identities. Phase 1's fixture stays unchanged. [Golden vectors](../verification/adr0005-golden-vectors.json) are specification data, not a runtime codec or passing runtime test.

**Alternative:** Generic maps/canonical JSON and extensible payloads. **Consequence:** Fixed binary schemas reduce interpretation choices but make changes explicit migrations. Numeric limits are v1 bounds, not performance claims.

### 3. Enrollment and epoch transitions

**Decision:** Enrollment is an out-of-band operator action against an empty event store with no prior custody enrollment. Its payload is `store[16] || epoch:u64=1 || authorization_id[16] || reason:text`; reason is nonempty. Genesis head is SHA256 of `"warband.genesis.v1\0" || enrollment payload`. Runtime credentials cannot enroll, replace a missing checkpoint or manufacture an operator authorization. The custodian records the authenticated operator UID and complete authorization payload in a durable administrative receipt; UID is u64 in the GENESIS/EPOCH history payload suffix. The genesis head hashes only the enrollment payload before that UID suffix. The operator UID is custody evidence, not an untrusted request field.

Epoch-change request payload is `old Ref || old_head[32] || new_epoch:u64 || new_seq:u64=0 || new_head[32] || authorization_id[16] || reason:text || unresolved_pending_record_hash[32]` (zero only if none). New epoch is exactly old epoch+1. New head must equal SHA256 of `"warband.epoch.v1\0" || old Ref || old_head || new_epoch:u64 || authorization_id || reason:text || unresolved_pending_record_hash`). Custodian history appends the request payload plus the authenticated UID:u64. Authorization IDs are unique for the store's complete custody history; exact replay of the latest successful administrative request returns its receipt, changed/reused authorization rejects. Preserve the previous epoch and pledge; do not append an automatic cancellation.

Operator quiesces both writers, preserves the old SQLite files/WAL and custody metadata, and starts an empty new epoch segment after investigation. No tasks, capabilities or accepted facts are silently carried from an untrusted segment. The new epoch is a separate task namespace, not an assertion that old authoritative facts were rolled back or became empty. Old tasks remain quarantined/integrity-unknown until their history is reconciled; only the runtime state boundary can establish new task facts. Retained epoch segments remain one logical event history, not independent authoritative ledgers. Epoch administration may remain interrupted/faulted until the operator completes installation and comparison; there is no automatic cross-store administrative transaction or runtime repair. A corrupt custody history cannot supply a trustworthy old head: stop for investigation, rather than allow epoch_change to invent one. Operator recovery does not declare missing work complete.

**Alternatives:** Owner-signed epoch requests provide transport-independent, reviewable authorization, but require protected key custody, rotation, revocation and replay handling; they are not selected for the current out-of-band local operator path. Automatic enrollment/reset from SQLite contents is rejected because it would let the rewriteable store establish its own trust anchor. **Consequence:** Local operator intervention avoids adding key management in Phase 2, while manual recovery remains an accepted availability cost.

### 4. Versions and acceptance table

**Decision:** Task version starts at 1 with TaskCreated and advances only on TransitionAccepted. Control revision is per task/run, starts at 0, and advances on grant, consumption, revocation, accepted transition or an attempt disposition. Attempt identity is immutable, distinct from both counters. All task/control/attempt lookups are scoped by store and epoch. A SQL acceptance transaction checks expected task/control values, current grant/consumption/revocation state, reference closure and uniqueness, and appends the event plus derived indexes atomically. Indexes are reconstructible; they are not a second authoritative ledger. Reads expose only the custodian-confirmed prefix.

| Event | Preconditions | Task/control change | Evidence | Unique key in addition to full event Ref |
|---|---|---|---|---|
| TaskCreated | New nonzero task/run/command; registered input producer | task=1, control=0 | Inline evidence ID + SHA256 of `"warband.task.v1\0" || task ID || run ID || command ID`; producing event is this event | task/run and command |
| ProposalRecorded | Existing incomplete task/run; matching expected version; exact NoOp shape | None | Canonical input and derived proposal fingerprint | proposal ID |
| AuthorizationRecorded permit | Current proposal/policy; recovery=stop; no approval required; matching control; unused capability ID | control+1 | Producer-2 deterministic decision over recorded proposal; inline evidence ID, producing event is this event | capability ID and proposal authorization |
| AuthorizationRecorded reject/require approval | Recorded proposal; no capability grant | None | Recorded decision and proposal reference | event Ref |
| DispatchClaimed | Permit; current task/control/policy; fresh elapsed-time check strictly before expiry at claim confirmation; not revoked/used; all proposal bindings match | control+1, consume one use | Authorization event and runtime-generated claim binding | capability use and attempt ID |
| ObservationRecorded | Existing confirmed claim; registered observer; matching attempt; one observation | None | Exact bounded observed bytes or explicit indeterminate outcome | attempt observation and evidence ID |
| EvaluationRecorded | Existing confirmed observation; registered evaluator; recomputed observation digest; same claim/criterion | None | Observation Ref/digest and evaluator verdict | observation evaluation and evidence ID |
| TransitionAccepted | Verified NoOpV1 evaluation; same claim; matching task/control; capability consumed by that claim and not revoked; current recorded policy version | task+1, control+1 | Evaluation -> observation -> claim -> authorization -> proposal chain | transition ID and accepted attempt |
| RejectionRecorded | Known stage/reason; registered producer; valid optional reference | None | Rejected-input digest; no raw secret-bearing input | event Ref |
| CapabilityRevoked | Existing grant, matching capability and control; not already revoked | control+1 | Registered policy producer's recorded operator/policy revocation reason | capability revocation |
| AttemptDisposition | Existing claim; matching control; no accepted transition | control+1 | Producing claim plus recorded recovery reason | attempt terminal disposition |

All uniqueness keys above include store/epoch. The same permit is not reissued as another grant after a claim. A recovery retry needs a newly authorized proposal/attempt after operator reconciliation, not resurrection of a consumed lease. Completion acceptance rejects any indeterminate disposition; completing a previously stopped attempt is not an automatic recovery rule. A duplicate accepted attempt returns the recorded result only if the complete binding agrees; it does not create another event or execute again. Concurrent acceptors serialize and still encounter the same SQL constraints. Replay derives these changes from validated recorded inputs without today's policy or clock.

**Alternative:** One counter for audit, task and control. **Consequence:** Rejected because a consumption event could invalidate its own result or allow unrelated state drift. Separate counters add explicit checks but keep each meaning stable.

### 5. Observer and evaluator trust

**Decision:** Producer registry v1: 1 runtime input normalizer, 2 deterministic policy/capability authority, 3 no-op observer, 4 NoOpV1 evaluator, 5 state/recovery boundary; each has version 1. Registration is compiled/reviewed configuration, not a caller-selected producer string. Persisted kind/producer pair and version must match the registry. Producer IDs are role identities, not OS credentials or cryptographic attestation.

Observer content is exactly the ObservationRecorded schema above, bound through its claim Ref to the full attempt/proposal/task/run/capability identity. A returned observation is produced only after the no-op returns; an interrupted/lost attempt is indeterminate. NoOpV1 evaluator independently recomputes the observation event digest and checks the confirmed reference chain, producer/version, outcome=returned, observed bytes=`NOOP`, criterion=1 and runtime-owned proposal criteria. It emits its own evidence identity/verdict. The state boundary alone applies acceptance rules; neither producer 3 nor 4 has a state-write API. An unknown or substituted producer, cross-attempt evidence or model success text cannot become a verified result.

These are separate modules/procedures in the same runtime process. Independence here is deterministic evaluation separate from proposal/executor claims, not process-compromise resistance. A compromised trusted process can fabricate its own inputs; OS/kernel/root compromise is outside this Phase 2 guarantee. Later worker isolation and real observation sources need separate reviews. Phase 2 rejects approval-required requests; valid human approval integration remains Phase 3 work.

**Alternative:** One producer's success boolean, or separate evaluator services immediately. **Consequence:** The boolean cannot establish independent evidence; extra services add identity/transport work before the no-op boundary is proven. Select separate responsibilities without claiming process isolation.

### 6. Proposed Phase 2 effect qualification

**Qualification status (2026-11-18).** The table defines a closed Phase 2 call graph. The Gate 0 amendment below selects only the custodian rows for conditional 3b activation. The entry review records implementation authority. ADR-0007 applies to its Phase 1 procedures only. E denotes direct or transitive effects. Mid and pure Low procedures remain transitively pure, and Low procedures never call upward.

| Eligible High E, planned location | Responsibility | Related High | Pure Mid decisions | Direct reviewed Low dependencies / effects |
|---|---|---|---|---|
| `cmd/warband:main` | Coordinate selected CLI command | `run_noop` | `parse_command`, `describe_command` | `read_arguments`, `write_result`, `exit_with_status` |
| `cmd/warband:run_noop` | Coordinate one task workflow under the writer gate | `reconcile_custody_audit`, `record_noop_authorization`, `perform_noop_attempt`, `record_noop_acceptance` | `describe_noop_result` | `acquire_writer_lock`, `release_writer_lock` |
| `src/runtime:record_noop_authorization` | Record task, normalized proposal and policy grant/rejection | `append_verified_event` | `decide_task_creation`, `normalize_noop`, `decide_authorization` | `read_confirmed_state`, `observe_time`, `generate_identity` |
| `src/runtime:perform_noop_attempt` | Record the claim and its bounded observation | `append_verified_event` | `decide_claim`, `describe_observation` | `read_confirmed_state`, `observe_time`, `generate_identity`, `invoke_noop_primitive` |
| `src/state:record_noop_acceptance` | Record evaluation and eligible completion/rejection | `append_verified_event` | `decide_evaluation`, `decide_acceptance`, `describe_rejection` | `read_confirmed_state`, `generate_identity` |
| `src/store:append_verified_event` | Coordinate one pledged event append | None | `validate_event_plan`, `validate_committed_event` | `send_prepare`, `sqlite_append_transaction`, `read_committed_bytes`, `send_confirm` |
| `cmd/custodian:main` | Coordinate startup/shutdown | `recover_checkpoint`, `serve_loop` | `validate_configuration`, `validate_custody_paths` | `read_configuration`, `decode_configuration`, `acquire_custodian_lock`, `release_custodian_lock`, `open_socket`, `bind_socket`, `listen_socket`, `close_socket`, `inspect_path_metadata` |
| `cmd/custodian:serve_loop` | Repeat one reviewed request workflow until shutdown | `serve_request` | `decide_service_continuation` | `observe_termination_request` |
| `cmd/custodian:serve_request` | Coordinate one authenticated request | `prepare_checkpoint`, `confirm_checkpoint`, `enroll_checkpoint`, `change_epoch`, `verify_checkpoint`, `record_custody_rejection` | `classify_request`, `decide_peer_role`, `describe_reply` | `accept_connection`, `read_request_bytes`, `decode_request`, `read_peer_credentials`, `encode_reply`, `write_reply_bytes`, `close_connection` |
| `src/custody:prepare_checkpoint` | Persist one validated pledge | None | `decide_prepare`, `validate_link` | `read_history_bytes`, `decode_history`, `encode_pending_frame`, `append_history_frame`, `fsync_history` |
| `src/custody:confirm_checkpoint` | Persist confirmation or return exact replay | `publish_head` | `decide_confirm` | `read_history_bytes`, `decode_history`, `encode_committed_frame`, `append_history_frame`, `fsync_history` |
| `src/custody:publish_head` | Publish selected head bytes durably | None | None | `encode_head`, `create_head_temporary`, `write_head_bytes`, `fsync_head`, `rename_head`, `fsync_custody_directory` |
| `src/custody:verify_checkpoint` | Read validated custody status and the earliest eligible receipt through a fixed tip | None | `validate_custody_history`, `validate_head`, `select_rejection_receipt` | `read_history_bytes`, `read_head_bytes`, `decode_history`, `decode_head` |
| `src/custody:recover_checkpoint` | Apply permitted metadata recovery | `publish_head` | `classify_recovery`, `validate_custody_history`, `validate_head` | `read_history_bytes`, `read_head_bytes`, `decode_history`, `decode_head`, `truncate_final_frame`, `fsync_history` |
| `src/custody:enroll_checkpoint` | Record authorized empty-store enrollment | `publish_head` | `decide_peer_role`, `decide_enrollment`, `validate_custody_history` | `read_history_bytes`, `decode_history`, `inspect_empty_store`, `read_peer_credentials`, `encode_genesis_frame`, `append_history_frame`, `fsync_history`, `fsync_custody_directory` |
| `src/custody:change_epoch` | Record separately authorized epoch transition | `publish_head` | `decide_peer_role`, `decide_epoch_change` | `read_history_bytes`, `decode_history`, `read_peer_credentials`, `encode_epoch_frame`, `append_history_frame`, `fsync_history` |
| `src/custody:record_custody_rejection` | Persist a denied-request metadata receipt under Option A | None | `describe_custody_rejection`, `validate_custody_history` | `read_history_bytes`, `decode_history`, `read_peer_credentials`, `hash_rejected_prefix`, `encode_rejection_frame`, `append_history_frame`, `fsync_history`, `fsync_custody_directory` |
| `src/runtime:reconcile_custody_audit` | Import verified receipts as audit-only events; selected Gate 1 direction; inactive until Gates 2/3 | `append_verified_event` | `validate_custody_receipt`, `describe_custody_audit_event` | `send_verify`, `read_confirmed_state` |

Each listed Low name denotes a narrow fixed technical operation, not a general callback or policy-bearing wrapper. Exact permitted callees are those in its row; related High calls are not an all-to-all permission. Pure `decide_*`, `validate_*`, normalization and description procedures call pure Low helpers only. Frame decoding checks representation and hashes, not eligibility policy; SQL constraints enforce the supplied plan rather than selecting a domain action. The three task subflows each expose a distinct durable responsibility; they are not forwarding wrappers. Public event/custody codecs are pure Mid decisions validating schema, identity and bounds over supplied values; they call pure Low packing, parsing and hashing primitives. Those technical primitives remain Low. No codec or reachable helper performs I/O, and the existing Phase 1 fixture classification is unchanged. Pure High may combine only pure Mid. The listed startup/loop procedures have no unlisted effects or imports. A future implementation must map every named operation to its concrete source procedure before review; renaming or splitting does not enlarge the allowed effect set. The custodian amendment and pinned-library startup qualification below are separately scoped; no other unlisted startup exception is granted. All socket, SQLite and filesystem APIs stay behind reviewed Low adapters; no technical handles enter Mid.

#### SQLite writer-open qualification

Proto approved this bounded slice 4 entry on 2026-11-19. The store coordinator may inspect the linked SQLite version, full source ID and compile options `THREADSAFE=1`, `OMIT_LOAD_EXTENSION` and `DQS=0`. All must match the §7 pin before opening a file. Its Low calls may open an existing database read-write, check actual write access to main, prepare/step/read/finalize the fixed profile statements, and close the connection.

The first SQL read must return application version 1 before any setting changes. Then set WAL, FULL synchronization and foreign keys, and read back all four profile values on the same connection. Success returns an owned opaque writer with a read-only snapshot of those observations. Any failure releases acquired resources and withholds the writer. Only the integration fixture creates a database or assigns its version. Append and denial import retain their separate entry gates.

In `src/store/writer.odin`, `open_writer` coordinates identity inspection, existing-file open, fixed profile statements and cleanup. In the private `sqlite.odin` adapter, `library_matches_pin` checks the library identity, `open_existing` opens with SQLITE_OPEN_READWRITE alone and checks `sqlite3_db_readonly` for main, and `release_connection` closes. `read_scalar` and `set_connection_option` prepare, step and finalize the fixed statements. The public profile accessor returns the captured values by copy. A successful opener owns the handle until close.

The two real-database cases passed locally on macOS ARM64 and the recorded Ubuntu x64 VM with the pinned static archive. Both live writers reported all four expected values. Independent read-only inspection after the version-zero refusal found version 0 and journal mode delete. The first macOS compile rejected an absolute foreign import path before running tests. A named Odin collection now resolves the exact pinned archive on both targets. The integration runner checks both named results and retains the report under `out/<target>/writer-open/`.

#### Isolated no-op live dispatch qualification

Proto authorizes an isolated Linux gate for one confirmed task and approval-free NoOpV1 proposal. The entry holds the existing writer lock through receipt reconciliation, permit issuance, confirmed claim, evidence comparison and the primitive call or recorded refusal. The runtime may sample BOOTTIME and audit wall time, generate new identifiers, read the confirmed bindings, and append only the bound permit, claim or dispatch refusal through the pledged store path. The no-op primitive returns the fixed four bytes. The observation and evaluation qualification follows below. State acceptance retains a separate gate.

Start the private grant interval before constructing the authorization. Require a timely observation at claim confirmation and immediately before dispatch. Consume the in-memory dispatch permission once. On a fresh execution with a valid durable permit and claim, return NoLiveGrantEntry and record RejectionRecorded (producer 2, stage 3, reason 9, related claim Ref, digest of the complete canonical claim). Failure to confirm a rejection withholds progress. Recorded expiry and claim time remain audit data. Only a separate test build may stop the issuer after confirmation and emit a witness from inside the primitive.

The operator names the proposal Ref. This increment reads one task/run and one proposal from a checkpoint-covered SQLite snapshot. Audit-only rows may coexist. Additional task, grant, claim or other state-changing records withhold dispatch. Issuance checks the task input digest, task/run identity, task version, registered policy and approval flag. Under the writer lock the runtime generates distinct-purpose IDs with Linux getrandom, constructs the permit and claim, and uses a capability-bounded confirmation deadline. Only timely receipt of the confirmed claim installs a dispatchable private entry. Recovery of an existing claim supplies durable evidence only.

Both processes reconcile outstanding custody receipts, compare the persisted permit, claim, version and proposal fingerprint against the authenticated prefix and enter the same dispatch procedure. The gate checks the private entry's permit, capability, claim and attempt bindings, samples BOOTTIME and clears the entry before calling the primitive. The fresh process receives the identical command arguments. It learns no elapsed-time origin from them. The refusal's wire reason 9 and related claim identify the evidence used. The process result names NoLiveGrantEntry.

| x64-review case | Construction start | Claim confirmed | Issuer exit bracket | Dispatch check | Primitive invocations |
| --- | ---: | ---: | --- | ---: | ---: |
| Issuing process | 511715 | 511737 | After dispatch | 511770 | 1 |
| Fresh execution | 512570 | 512591 | 512613–512614 | 512632 | 0 |

All observations are BOOTTIME milliseconds. The parent bracketed issuer death by sampling before SIGKILL and after reap. The fresh process reached the gate 62 ms into the original 90,000 ms interval. The fixture independently checked both checkpoint-covered events before terminating the issuer, counted witness lines emitted inside the primitive, and verified the subsequent reason-9 record and its claim digest through custody confirmation. The transcript is `.local/noop-gate-proof.log`, SHA-256 `af24964de0d1c8210d2f89f36188e047cd342fb811df263616b2ca2094b9fb8a`.

The first build stopped before tests because the timing-outcome switch needed explicit partial-switch syntax. The first paired run stopped during independent claim inspection because its assertion used the attempt field offset for the capability ID. The corrected assertion compares the capability at bytes 104–119. The paired test passed with the pinned Linux archive and compiler. The adjacent four writer/provisioning tests and the receipt reconciliation suite including the post-COMMIT kill case also passed locally.

#### Isolated no-op observation and evaluation qualification

Under the existing writer gate, the registered observer may compare the actual bounded primitive return, generate an evidence ID and append one ObservationRecorded for the confirmed claim. A fresh execution with that claim and no surviving return records Indeterminate. A dispatch refusal remains separate audit evidence. The evaluator receives a confirmed observation Ref, reads its canonical bytes from the custody-covered SQLite prefix, validates the claim and proposal bindings, computes the observation digest and appends one EvaluationRecorded with its own evidence ID. Both appends use prepare, commit, read-back and confirm. A retry resumes from the first missing record. Neither procedure may append a transition or advance task or control versions.

The observer checks the actual four-byte return against ASCII `NOOP` before selecting Returned. Without a surviving matching return it selects Indeterminate. The evaluator takes the requested proposal and confirmed observation Refs, obtains a fresh authenticated checkpoint and SQLite read snapshot, decodes the stored kind-5 bytes and recomputes SHA-256 over the event domain and the exact persisted body. It checks the producer, NoOpV1 criterion, claim, permit, proposal fingerprint and task/run bindings. Fresh evidence IDs distinguish the records. Re-reading an existing verdict also requires matching its digest, claim, observation and verdict.

On x64-review the returned case produced one invocation, a producer-3 Returned observation and a producer-4 Verified evaluation. After SIGKILL between primitive return and observation, restart produced zero further invocations, a distinct reason-9 dispatch refusal, an Indeterminate observation and a Rejected evaluation. Its second restart preserved all rows and custody tip 18. After SIGKILL at confirmed observation (tip 14), restart appended only the missing evaluation (tip 16). The next run returned the stored verdict with all rows and tip 16 unchanged. None of these events changes task/control versions or accepts completion.

The existing proof build adds stops immediately after return and after confirming a returned observation. The default build contains neither stop. The harness independently re-hashed the stored observation body, checked both producer IDs, criteria, evidence IDs and references, and compared the complete event prefix with the custodian. The local transcript is `.local/observation-evaluation.log`, SHA-256 `7fb841d19030218ed314415a1ca095158d6d217fff5278ea003de563c2bfe5a5`.

#### Isolated Linux receipt reconciliation qualification

The isolated reconciliation entry acquires a process-owned exclusive flock on the protected database inode before opening a verified writer. All writers participating in this protocol use the same gate. Fail immediately on contention, within ADR-0008's five-second lock ceiling. Hold it through tail comparison, custody requests, SQLite transaction, confirmation and the final progress decision. The operator supplies immutable paths and the expected peer identity while the pass runs.

Activate only receipt reconciliation and its pledged audit append. The runtime client connects to the runtime Unix socket, checks kernel SO_PEERCRED against the configured custodian UID before transmitting, and sends only prepare, confirm and verify. BOOTTIME bounds elapsed waits. Only new audit events use CLOCK_REALTIME in Unix microseconds. Retry and recovery derive pledges from persisted bytes. Store effects are fixed prepared reads and bound inserts or watermark updates in a single transaction. The state-crafted Linux harness may provision and inspect disposable fixtures. Dispatch and generic event writes remain separately gated. The post-COMMIT test qualification follows below.

For epoch N supply each retained database (with its preserved WAL) and its original WBCR epoch-change request, in order from epoch 1 through N−1. The trusted operator keeps the installed path, archives and companions stable while the pass holds the active inode lock. The runtime opens each archive read-only, checks version 1 in a read transaction, decodes the event sequence and recomputes links over the persisted canonical bodies. The request binds its old checkpoint to its recomputed successor genesis head. Check that head against the start of the next segment and ultimately the checkpoint from the authenticated live custodian. Missing segments, a substituted transition, an unexplained suffix or a mismatching archived prefix withhold progress. This comparison grants no authority to resume old tasks.

After active tail classification, compare bindings across the verified segments in event order with the authenticated earliest-receipt stream, starting at ordinal zero. Require the full frame digest and the same store-wide ordinal and record hash. Check each segment's local watermark against its own rows. An empty successor segment inherits no index rows. Its comparison still accounts for imports in every retained segment. A stale derived index blocks for verified reconstruction. An explicit retry supplies the ordinal and hash and returns the compared full event reference. If the fixed interval also contains new imports, an exact retry withholds progress for a normal reconciliation pass.

`src/runtime:run` owns the lock, fixed tip and progress decision. The client package owns the bounded Linux socket exchange, elapsed/wall-clock observations and descriptor adapters. `src/store:append_verified_event` prepares the pledge, rechecks the predecessor and local watermark in the write transaction, and re-reads the committed row for exact confirmation. `confirm_stored` uses the same comparison during recovery. The isolated entry exits successfully only after the gate decision. Production append emits only the selected Option A event. Runtime verification decodes the ten registered kinds for prefix comparison. The process uses the ADR-0008 bounded arena, SQLite hard heap cap and connection cache setting. The pass charges repeated validation work conservatively against its visit budget. Confirmed capacity, failure-at-limit behavior and performance remain due under the existing verification plan.

**Local evidence (2026-11-20).** The Linux harness exercised all four named restart dispositions, an inconsistent watermark, a changed persisted timestamp, lock contention, and a wrong custodian UID. A second pass after exact confirmation preserved the event, binding, watermark and custody tip. A two-epoch fixture verified an old receipt against its archived event, rejected missing or contradictory handoffs, imported a later denial into the fresh segment and returned the original event Ref on exact retry. Damaged archived data blocked progress. The fixture used real UIDs, the provisioned v1 store, the pinned importer and the real custodian on x64-review.

Early builds rejected the foreign import declaration, immutable array slices and an untyped hash-domain constant before test execution. The first harness run expected no change to custody history after the client rejected the peer UID. The real custodian recorded the empty connection as required. The corrected check verifies zero captured bytes, an unchanged checkpoint and no SQLite change. The final target transcript is retained in `.local/reconciliation-final.log`, SHA-256 `8367876c713caadf972dfd1b26ca73cbd71477c2ace281cfd2bea86e6ca5ba85`. The four adjacent writer tests also passed. The later process-kill run is recorded below.

#### Post-COMMIT process-kill proof

On 2026-11-20 Proto authorized one Linux test build to send SIGSTOP to itself in `append_verified_event`. The compile-time branch is the first statement after `commit_import` succeeds, before watermark read-back and exact confirm. The default binary omits that branch. The parent waits up to 65 seconds for the exact fault child PID to report SIGSTOP, sends SIGKILL, and requires it to be reaped with status −9 and empty stdout. Both restarts use the default binary.

On the recorded x64-review target, independent reads after death found the original committed custody checkpoint, its exact successor PENDING pledge at tip 3, and one SQLite event, binding and watermark at receipt ordinal 1. The first restart reported PendingConfirmation, cleared the pledge and advanced the checkpoint to the event head at tip 4. The second reported Ready at tip 4. All three SQLite rows matched byte-for-byte after both restarts.

The focused run and complete reconciliation harness exited 0. The full local transcript is `.local/kill-proof-reconciliation.log`, SHA-256 `1a980c9c534b7bae003bd4cc2dbdc140841787c27e99e95fe012d4c4b21f8020`. Two initial builds stopped before tests because the pinned compiler rejected a conditional import and then reported an unused import in the normal variant. A file-scope Linux signal constant resolves both.

#### Operator store provisioning qualification

After successful custody enrollment observes the empty journal directory, the operator keeps that directory under exclusive control with the runtime quiesced. Run `provision-store <database-path>` there before handing the store to its writer. Ordering and directory ownership are operator preconditions. The command does not authenticate a custody peer or change directory permissions.

`cmd/provision-store:main` reads one path, calls `src/store:provision_store`, reports failure and exits. Provisioning may exclusively create and close one owner-only file, inspect the pinned library identity, open that file read-write, enable and read back foreign keys, execute the fixed schema transaction below and close SQLite. A failed transaction is rolled back on close. On any failure after acquisition, retain the newly created path for operator inspection, including when commit or close is uncertain. An existing path always refuses a retry. No automatic deletion or adoption is authorized.

The integration runner builds the operator executable at `out/<target>/provision-store` against the same project-local archive as the writer. Its two provisioning cases passed on native macOS ARM64 and the Ubuntu x64 review VM, alongside both existing writer-open cases. A freshly provisioned file admitted the verified writer and SQLite returned extended error 787 for an unbound watermark. The refused existing file matched its original bytes and retained its fixture row and version zero. The embedded SQL file matches the reviewed DDL byte-for-byte. The first macOS build stopped before tests because the compiler required an explicit NUL-terminated C string for the embedded SQL.

#### Gate 0 custodian amendment (2026-11-18)

The owner directed Gate 0 after slice 3a landed at `67d55f6`. The 3b qualification covers exactly the three `cmd/custodian` rows and the eight `src/custody` rows in this table, with only their listed call edges. Activation requires the entry conditions in the [3b entry record](../engineering/phase2-entry-review.md#slice-3b-gate-0). Runtime audit import, SQLite and no-op execution retain separate entry gates.

**First history creation.** Enrollment and denial recording are the two paths that may create the initial history file. In both, finish the append, sync the file and sync its protected parent directory before acknowledging or exposing the first durable record. Preserve that ordering when a pre-enrollment denial precedes GENESIS. If creation or directory durability is uncertain after a failed attempt, require reconciliation and successful synchronization before further protected progress. A write or sync failure follows CHECKPOINT_STORAGE_FAULT with a zero receipt. Test a first pre-enrollment denial with directory sync failing after file sync, alongside a successful durable denial.

**Verify.** A valid, authorized verify request calls only the read-only verify workflow. Read head and history from a serialized custody view, validate their relationship, bind the cursor to that tip and select the earliest eligible receipt. Return the applicable fault/readiness state on disagreement. Recovery, truncation and publication belong to explicit recovery entry. Denied requests continue through the separate rejection-recording workflow. Verify repeated reads against the same state and verify that an inconsistent head remains available as evidence after the diagnostic reply.

**Enrollment.** The proposed initial store layout uses a dedicated, operator-controlled empty journal directory while the runtime writer is quiesced. `inspect_empty_store` observes that fixed, protected directory directly and read-only. Require safe path ownership, an empty directory and exclusion of concurrent writers through the GENESIS decision. A missing, substituted, unreadable, populated or changing directory fails enrollment. Treat existing DB, WAL, journal or other entries as populated. A zero-length DB or absent custody head alone cannot establish emptiness. Keep custody metadata in its separate directory: prior valid epoch-zero denial receipts can coexist with an unenrolled store. Check validated custody history independently for prior GENESIS. Reading SQLite rows or opening a writable database requires a separate graph decision.

**Peer authority.** Bind the operation to the resolved listener and connected kernel credentials. Enrollment and epoch change re-read credentials from the same accepted connection and rerun the operator decision at the effect boundary. The Linux proof uses distinct custodian, runtime, operator and unlisted UIDs. Record successful operator enrollment and runtime prepare/confirm/verify, protocol denial of runtime administration, unlisted-peer denial, and real OS denial of direct runtime access to protected files and paths. Retain actual identities, errno values, redacted replies and persisted denial receipts. The Linux integration harness is a separate host-level check; its positive and negative outcomes require execution on the recorded target.

#### Isolated Linux custodian implementation (2026-11-18)

Proto approved a Linux elapsed-time Low adapter for request I/O and startup recovery. Add `wb_millis` to the `serve_request` and `recover_checkpoint` rows, including bounded socket reads and writes beneath the request row. It reads `CLOCK_BOOTTIME` for the 30-second request and 60-second recovery deadlines. The separate live-capability clock amendment retains its Proposed status.

| Qualified workflow | Concrete implementation and effects |
| --- | --- |
| Startup and shutdown | `cmd/custodian/main_linux.odin:main` parses the store and three distinct identity roles. `wb_lock` opens and validates the protected path components and takes the lifetime custodian lock. `wb_listen` creates, binds and listens on the two Unix sockets. `wb_close` and `wb_unlock` release descriptors. |
| Serving a request | `serve_loop` uses `wb_wait` to select a ready listener. `serve_request` accepts, reads, obtains connected credentials, decodes WBCR, calls the existing peer decision and routes the operation. It encodes WBRS, writes within the deadline and closes. A single process serializes both endpoints. |
| Prepare, confirm and denial | Same-named High procedures in `src/custody/linux/service_linux.odin` reuse the pure codecs and validated history. `append_record` encodes a frame, then `wb_append` completes the write and syncs history. Before enrollment it also syncs the directory to settle any uncertain first creation. Confirm publishes the head after the commit frame is durable. |
| Enroll and change epoch | Both procedures call `wb_peer` again on the accepted descriptor. `wb_empty_journal` inspects the operator-owned, read-only journal directory at enrollment. The isolated fixture grants the runtime no write access there. The trusted operator keeps the journal quiescent through the decision. Authorization replay compares the whole request and observed UID against validated history. |
| Verify and recover | `wb_size` and `wb_read` read bounded history and head files. Verify selects the earliest eligible receipt. Startup recovery uses `wb_sync_history` for a proven torn suffix and file sync. `publish_head` uses `wb_publish` to create, write and sync the temporary head, rename it and sync the directory. Explicit operator restart revalidates history and republishes an enrolled head to settle an uncertain prior rename. |

The C adapters in `src/custody/linux/native.c` use the pinned compiler and system libc. [Target evidence and reproduction](../verification/isolated-linux-custodian.md) cover real identity separation, first-create failure and recovery after process termination. The custody process supplies no event-store transaction or user-facing task execution.

#### Pinned SHA-256 library startup qualification — approved 2026-11-12

After review identified automatic CPU observations, the owner explicitly approved the narrow CPU checks/cache-write exception for the standard SHA-256 library. At pinned Odin source `8b35c86efb78e9ab5223673a07e02fc2a6884191`, language startup may invoke only these additional Low technical initializers through `core:crypto/sha2` → `core:sys/info`; this is not a general application startup or High-to-Low permission.

| Platform | Exact initializer boundary | Observations and writes |
|---|---|---|
| macOS ARM64 | `cpu_darwin_arm64.odin:_init_cpu_features`; `cpu_arm.odin:_init_cpu_name` | Read only the pinned functions' fixed `hw.optional.*` and `machdep.cpu.brand_string` keys using `sysctlbyname`; populate library-owned in-process feature/name caches |
| Linux x64 | `cpu_intel.odin:_init_cpu_features`; `cpu_intel.odin:_init_cpu_name` | CPUID/XGETBV observations; populate library-owned in-process feature/name caches |

Only feature results select SHA acceleration; the incidental name cache grants no authority. Codec calls remain supplied-value decisions. This permits no network, storage, persistent writes, caller-selected query keys or policy decisions. A new platform, initializer, changed compiler/library pin or broader effect requires another scoped review. No custom CPU probe, startup callback or replacement crypto implementation is introduced.

**Alternative:** General effectful Mid or unrestricted High-to-Low permission. **Consequence:** Rejected: universal Mid purity and bounded dependencies are preserved at the cost of maintaining an explicit graph. An implementation with additional startup/subflow procedures must return for a scoped graph update, not relabel the same violation.

### 7. SQLite source and integration profile

**Approved build input:** Use the official SQLite 3.54.1 amalgamation. [Release notes](https://www.sqlite.org/releaselog/3_54_1.html) identify the release/source; [the download page](https://www.sqlite.org/download.html) publishes its SHA3 digest. Review found a 32-bit heap-buffer-overflow fix plus other reported corrections relative to 3.54.0; this is release review, not a source audit or a claim that no vulnerabilities exist.

| Input | Reviewed identity |
|---|---|
| Source URL | `https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip` |
| Archive size | 2990966 bytes |
| Archive SHA-256, independently computed | `0a9c8e34352dad46006aa82836d5383bff9dc6bc9ce5a60553c05aa30e6ad1f9` |
| Archive SHA3-256, matches upstream | `92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30` |
| sqlite3.c SHA3-256, matches release notes | `e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81` |
| SQLITE_SOURCE_ID, verified in archive header | `2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76` |

The archive and source digests were independently checked against downloaded bytes; no SQLite code was compiled or executed in this documentation task. Future project-local static build: compile only sqlite3.c with the platform-pinned Clang C compiler, `-O2 -fPIC -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DQS=0`, and archive it as `.local/dependencies/sqlite/<source-id>/<target>/libsqlite3.a`. Record the complete compiler/version/flags, archive/object digests, target, compile options and final executable linkage. The proposed static archive is a new reviewed dependency; no runtime build is performed by this amendment. No host SQLite discovery or fallback. Keep the existing Odin/LLVM/runner pins unchanged. Check `sqlite3_libversion_number()==3054001`, exact `sqlite3_sourceid()` and required compile options at startup.

Use a minimal reviewed Odin C-ABI binding to this explicit project-local archive, opaque sqlite3 handles only in Low, and prepared statements with bound values; no SQL from proposals. The pinned Odin source demonstrates `foreign import` and C calling conventions in [core/c/libc/stdlib.odin](https://github.com/odin-lang/Odin/blob/8b35c86efb78e9ab5223673a07e02fc2a6884191/core/c/libc/stdlib.odin#L5-L22). The static C link checks below exercise Linux x64 and macOS ARM64. The Odin binding requires its own implementation and verification.

On every writing connection, set and query `journal_mode=WAL`, `synchronous=FULL`, `foreign_keys=ON`; reject any different effective value. Disable extension loading; use no custom VFS, optional extensions or unsafe synchronization settings. Pin the SQLite schema version at 1 and verify schema/constraints at open. The [SQLite synchronous documentation](https://www.sqlite.org/pragma.html#pragma_synchronous) describes WAL/FULL durability assumptions. Linux fault evidence must identify the actual filesystem, VFS, VM disk/cache/flush profile and SQLite compile options. macOS is functional/encoding development evidence only; it supplies no durability or Linux peer-credential claim. Source retention and clean rebuild proof remain release obligations.

**Alternative:** Independently pinned distribution libraries on each OS. **Consequence:** Project-local source adds a build/patch obligation but avoids changing library behavior under host upgrades. The build authorization and native probe results follow.

#### SQLite static build evidence

On 2026-11-18 Proto approved a six-file, 250-added-line build-only increment. The build script `scripts/build_sqlite.sh` verifies both SHA3-256 digests and the full source ID before compiling. It uses the flags in §7 and deterministic `llvm-ar rcsD`. The archive directory uses the hash component of the source ID. A fresh temporary build must pass the linked identity probe in `scripts/verify_sqlite_build.c` before its archive is installed.

| Native target | Clang | sqlite3.o SHA-256 | libsqlite3.a SHA-256 |
| --- | --- | --- | --- |
| Ubuntu 24.04 x64, x64-review | 19.1.1 | `edb9b0a0e35fb1af7b9c95a5e7ab7e452490ae37089f780a260aabbf7eeae689` | `7e4653fb2880a7262413d61da9fd21db8688c4c38f6da942b0757f3ef9dbc0fb` |
| macOS ARM64 | 19.1.7 | `1eeb5648072f4bb07634402f77f58b0abd3f80a8053d6337995ff35582cf9d01` | `0ec0ba3b6da57cd84e593a301c64e7a3a3259c1a82b70d8a4222dacc5b2dd549` |

Two fresh builds on each target reproduced its object and archive digests. Both native probes reported 3054001, the exact source ID above and all three required compile options. Linux linkage inspection showed libc and the loader. macOS showed only libSystem. Each CI job retains its compiler identity, flags, object and archive digests, complete option list and executable linkage in `out/<target>/sqlite-build.log`. A scratch build with an incorrect source digest stopped before compilation and archive installation. Three governance fixture checks initially reported broken links because their documentation-only trees omit scripts. The record now names the script paths directly. These results cover library identity and native linking. Connection settings and store behavior require separate evidence.

#### Schema v1 for events and denial imports

Operator provisioning requires exclusive creation of a new database at the selected store path. With foreign keys enabled, run the following as one transaction. On any error roll back and withhold the store from use. An existing file, including an unversioned file, is ineligible for provisioning. Ordinary writer open continues to require an existing version-1 database.

```sql
BEGIN IMMEDIATE;
CREATE TABLE events (
  store_id BLOB NOT NULL CHECK(length(store_id)=16 AND store_id<>zeroblob(16)),
  epoch BLOB NOT NULL CHECK(length(epoch)=8 AND epoch<>zeroblob(8)),
  sequence BLOB NOT NULL CHECK(length(sequence)=8 AND sequence<>zeroblob(8)),
  canonical_event BLOB NOT NULL,
  PRIMARY KEY (store_id, epoch, sequence)
) STRICT, WITHOUT ROWID;
CREATE TABLE denial_imports (
  store_id BLOB NOT NULL,
  custody_ordinal BLOB NOT NULL CHECK(length(custody_ordinal)=8 AND custody_ordinal<>zeroblob(8)),
  record_hash BLOB NOT NULL CHECK(length(record_hash)=32),
  epoch BLOB NOT NULL, sequence BLOB NOT NULL,
  PRIMARY KEY (store_id, custody_ordinal),
  UNIQUE (store_id, epoch, sequence),
  FOREIGN KEY (store_id, epoch, sequence) REFERENCES events(store_id, epoch, sequence)
) STRICT, WITHOUT ROWID;
CREATE TABLE import_watermarks (
  store_id BLOB PRIMARY KEY,
  last_imported_ordinal BLOB NOT NULL,
  FOREIGN KEY (store_id, last_imported_ordinal) REFERENCES denial_imports(store_id, custody_ordinal)
) STRICT, WITHOUT ROWID;
PRAGMA user_version=1;
COMMIT;
```

Store complete canonical event bytes and require their decoded Ref to match the row key. Encode epoch, sequence and ordinal keys as the existing eight-byte little-endian u64 representation. Compare decoded numbers for ordering. The receipt ordinal spans epochs within a store. An absent watermark row means zero imports.

Hold the writer gate across **custody prepare → SQLite commit → custody confirm**. In the single SQLite transaction append the event, bind its full Ref to the receipt identity and advance the watermark to that receipt's ordinal. On retry compare the stored hash at the same store and ordinal. A different hash is a conflict. An exact identity still requires verifying the bound event bytes and custody confirmation before reporting success. Never overwrite a conflicting binding.

At pass start snapshot the custody tip. Page by authenticated verify over validated custody history through that fixed tip. PENDING and COMMITTED frames consume ordinals too, so eligible receipt ordinals can have gaps. Only a verified response covering the interval can establish that it has no eligible receipt. A missing interval blocks protected progress. Leave later receipts for the next pass. The watermark tracks the last imported receipt and may be below the tip of a completed pass.

Rebuild the derived rows from the confirmed event prefix and verified custody history. In custody order, match each eligible 203-byte REJECTION frame to its audit event by SHA-256 of the entire frame, including its record hash. Require kind 8, producer 5, stage 7, reason 13, absent related Ref, and a unique matching event in the same store. Bind the event Ref to the ordinal and record hash from custody. Reconstruct the watermark through the last consecutively accounted-for eligible receipt. Conflicting, duplicate or unexplained bindings block progress. A SQLite watermark alone cannot establish custody confirmation.

**Acceptance case ([target evidence](#post-commit-process-kill-proof)).** Kill the importer after SQLite COMMIT returns and before it sends confirm. On restart, require `PENDING_CONFIRMATION`, validate the confirmed prefix and exact pending pledge, then resume confirm. Withhold protected progress until confirmation and reconciliation through the snapshot tip. Assert one event, one receipt binding and the receipt ordinal as watermark. A second pass must leave all three unchanged. If confirmation already completed, `CONFIRMED_RESPONSE_PENDING` returns the compared result. `PENDING_EVENT_MISSING` and `UNATTESTED_TAIL` preserve evidence and halt for the operator. An interruption after prepare alone can cause `PENDING_EVENT_MISSING` during normal operation.

### Option A: bounded durable custody rejection receipt — selected by Proto, 2026-10-21

**Operator decision:** Proto selected Option A at Gate 1 on 2026-10-21 and explicitly accepted unbounded total denial-history growth as a Phase 2 limitation. At that Gate 1 decision, ADR-0005 acceptance and Phase 2 entry were still pending. The acceptance metadata and dated entry records above govern current status. This historical selection established the denial-receipt design; the later codec slices implement representation only. Operational custody and receipt import remain deferred.

**Frame:** Type 5 REJECTION uses the existing v1 custody frame header/hash chain and a fixed 88-byte payload, in this exact order: configured store ID[16], custody epoch:u64, fault code:u16, captured-prefix length:u32, request-complete:u8, bounded-request digest[32], peer-observed:u8, kernel UID:u64, kernel GID:u64, kernel PID:u64. Thus its complete frame is 203 bytes. Epoch 0 denotes pre-enrollment custody metadata only, never a runtime event reference. Fault code is a non-READY value from the existing status registry (1–19). The store/epoch describe the custodian's actual context, not an identity asserted by the denied caller.

The captured prefix is at most 65547 bytes (11-byte request header plus maximum payload); it may be empty when authentication rejects before request acquisition. Request-complete is 1 only for an exact fully observed bounded request, otherwise 0. Compute the digest as SHA256 of `"warband.custody.denial.v1\0" || captured_length:u32 || request_complete:u8 || captured_prefix`. Never claim this identifies unread bytes, read an unbounded request to complete a digest, or persist the raw prefix. Kernel credentials come only from the connected local socket. Peer-observed is 1 only when all UID/GID/PID values were obtained; otherwise it is 0 and all three fields are zero. A caller-supplied identity never fills these fields. PID is provenance, not authorization.

**Persistence and acknowledgment:** Serialize the denial record with other custody history writes. Append one complete REJECTION and fsync the history (and initial directory entry if newly created) before returning a denial response claiming a durable receipt. Return its record hash as the receipt. Each observed denial is a new ordinal, not an idempotent success or an authorization. REJECTION participates in custody ordinal/hash validation but never moves the committed event head, publishes a head file, grants a capability, or replaces/clears a PENDING pledge. Existing prepare/confirm exact-replay receipts remain unchanged even if later denial records exist.

If append, short-write completion or synchronization fails, enter `CHECKPOINT_STORAGE_FAULT`: do not claim durable denial, permit the request, advance state, or acknowledge protected progress. A best-effort nondurable fault reply has a zero receipt, then closes the connection; it is not an audit acknowledgment. Block further mutations until operator reconciliation establishes storage health and actual retained records. Do not recursively try to record storage failure on the same failed storage. Verification may expose the fault without claiming durability. A torn final REJECTION follows the same strict final-frame recovery rule as other custody frames; complete bad hashes or interior corruption remain `ATTESTATION_HISTORY_FAULT`.

**Denial-growth disposition — selected by Proto, 2026-10-21:** Each REJECTION frame remains bounded to 203 bytes, and request-prefix acquisition remains bounded as specified above. Total receipt count and retained history size have no cumulative bound in Phase 2. Proto accepts the resulting disk-exhaustion and availability risk as a Phase 2 limitation; reconciliation work can also grow with retained history. Per-receipt bounds are not a claim of bounded aggregate growth or production denial-load resilience.

Do not silently drop, sample, coalesce, prune or overwrite required denial receipts, or weaken durable-before-acknowledgment behavior to stay within a storage budget. Storage exhaustion follows `CHECKPOINT_STORAGE_FAULT` above: no falsely durable receipt, no permitted denied operation and no protected progress until operator reconciliation. This selection introduces no quota, automatic retention policy, batching or remote custody. Any later aggregate bound or retention mechanism requires explicit review preserving audit completeness; no such mechanism or durability proof is implemented here.

**One event history, no new authoritative ledger:** Custody rejection receipts are retained integrity/audit outbox metadata, not task facts or a second authoritative projection. The existing authenticated verify operation can return one receipt at a time using the cursor/reply fields above. A cursor beyond the returned tip rejects; a missing requested interval is not silently treated as imported. The runtime verifies the complete receipt, custody context/hash provenance and kernel-derived producer source before recording `RejectionRecorded`, producer 5, stage 7, reason 13, related reference absent, rejected-input digest=SHA256 of the complete REJECTION frame. That event is audit-only and changes no task/control version. The import identity `(store, custody ordinal, record hash)` is unique; a reconstructible index prevents duplicate audit events without creating another authority store. Raw requests and credentials beyond the specified peer metadata never enter event payloads.

At startup and before a dispatch/publication gate, snapshot the custody tip and reconcile unimported receipts through that watermark into the single event history, using normal prepare/commit/confirm for each imported event. Later denials remain durably retained for the next reconciliation; no batch attestation is introduced. A stopped runtime leaves receipts retained, not silently discarded or represented as completed imports. Import failure withholds protected progress and requires the named recovery disposition. Pure replay uses supplied recorded events/verified custody data; it does not perform live receipt retrieval. Custody metadata never authorizes a state transition, and no receipt is automatically deleted after import. This specifies the handoff required by WB-CON-007 while preserving ADR-0003; end-to-end audit coverage still requires later implementation evidence.

The two receipt-related High procedures in the effect table are limited to these operations. Gate 1 selects their design direction; they gain no implementation permission before ADR acceptance and separate Phase 2 entry authorization. They are outside the first three pure code slices in the current execution task. Owner-signed requests, remote custody, batching and new tools are not introduced.
