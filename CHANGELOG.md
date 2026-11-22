# Changelog

All notable changes to Warband are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Record changes under explicit dated version headings, newest first. Start at
`0.0.0`; Git tags use the `v` prefix. Subsequent version links compare the previous
and current tags. Only include categories that contain notable changes.
Add a version entry when publication is authorized, using the actual publication
date. Draft candidates are documented in their PR and evidence record until then.

## 0.0.39 - 2026-11-21

### Added

- Verified three interruptions around custody Prepare. Recovery removes exactly the validated 83-byte final PENDING prefix and preserves the earlier history. The original denial receipt remains outstanding. [PR #77](https://github.com/progentic/Warband/pull/77)

## 0.0.38 - 2026-11-21

### Added

- Verified recovery after the custodian dies at four points during head publication. The importer reports uncertainty even when the new head is visible. After restart, exact confirmation returns the original receipt. [PR #76](https://github.com/progentic/Warband/pull/76)

## 0.0.37 - 2026-11-21

### Added

- Verified that an importer killed after custody confirmation and before caller acknowledgment returns the original event reference on exact retry. The retry and ordinary restart preserve the stored rows and custody checkpoint. [PR #75](https://github.com/progentic/Warband/pull/75)

## 0.0.36 - 2026-11-21

### Added

- Verified that replay counts a denial receipt as outstanding after the importer dies with its SQLite transaction committed. The count drops to zero once custody confirms the import and stays zero on a second restart. [PR #74](https://github.com/progentic/Warband/pull/74)

## 0.0.35 - 2026-11-21

### Added

- Added `replay-noop` to reconstruct task and control state from custody-confirmed events. Replay withholds the whole projection when the event chain or its references fail validation. [PR #71](https://github.com/progentic/Warband/pull/71)

## 0.0.34 - 2026-11-21

### Added

- Recorded startup work, visits per confirmed no-op task and the overhead of one concurrent denial on x64-review. [PR #66](https://github.com/progentic/Warband/pull/66)

## 0.0.33 - 2026-11-21

### Added

- Added `accept-noop` to accept a verified no-op evaluation once and return the recorded transition on an exact retry. [PR #65](https://github.com/progentic/Warband/pull/65)

## 0.0.32 - 2026-11-21

### Added

- Record Linux no-op observations and independently evaluate their confirmed bytes. On restart, a lost return is recorded as indeterminate and receives a rejected verdict. [PR #64](https://github.com/progentic/Warband/pull/64)

## 0.0.31 - 2026-11-21

### Added

- Added a Linux no-op dispatch gate that requires a confirmed claim and a live grant from the issuing runtime. A fresh runtime records a refusal against the claim. [PR #63](https://github.com/progentic/Warband/pull/63)

## 0.0.30 - 2026-11-21

### Changed

- Accepted the Linux capability expiry rule. Suspend counts toward the 90-second lifetime, and live grants expire when the issuing runtime exits. [PR #61](https://github.com/progentic/Warband/pull/61)

## 0.0.29 - 2026-11-21

### Added

- Added deadline checks over supplied elapsed time for tasks, operations, lock waits and capabilities. [PR #60](https://github.com/progentic/Warband/pull/60)

## 0.0.28 - 2026-11-21

### Added

- Recorded measured receipt-import visits and denial storage growth on x64-review, with raw observations for independent verification. [PR #59](https://github.com/progentic/Warband/pull/59)

## 0.0.27 - 2026-11-20

### Added

- Added a Linux process-kill test showing that restart confirms a committed receipt import exactly once and preserves its SQLite rows. [PR #57](https://github.com/progentic/Warband/pull/57)

## 0.0.26 - 2026-11-20

### Added

- Added `reconcile-custody` to import denial receipts, finish pending confirmations, and verify retained SQLite segments before admitting progress. [PR #56](https://github.com/progentic/Warband/pull/56)

## 0.0.25 - 2026-11-20

### Added

- Added `provision-store` to create a new SQLite store with schema v1 and refuse existing paths. [PR #55](https://github.com/progentic/Warband/pull/55)

## 0.0.24 - 2026-11-19

### Added

- Verify the SQLite library identity, schema version and connection settings before admitting a writer. [PR #53](https://github.com/progentic/Warband/pull/53)

## 0.0.23 - 2026-11-18

### Added

- Added a pinned static SQLite 3.54.1 build with native identity and linkage checks on Linux x64 and macOS ARM64. [PR #51](https://github.com/progentic/Warband/pull/51)

## 0.0.22 - 2026-11-18

### Added

- Added an isolated Linux custodian that authenticates local peers, persists checkpoints and denial receipts, and supports read-only verification. [PR #49](https://github.com/progentic/Warband/pull/49)

## 0.0.21 - 2026-11-18

### Changed

- Activated isolated slice 3b on the verified Linux target after the owner reviewed the open denial-history growth exception, WB-EXC-001. [PR #48](https://github.com/progentic/Warband/pull/48)

## 0.0.20 - 2026-11-18

### Changed

- Updated the developer and maintainer guides to cover the current audit codecs, custody protocol and slice 3b prerequisites. [PR #47](https://github.com/progentic/Warband/pull/47)

## 0.0.19 - 2026-11-18

### Changed

- Documented the custodian’s Gate 0 effect boundaries and the prerequisites for activating slice 3b. [PR #46](https://github.com/progentic/Warband/pull/46)

## 0.0.18 - 2026-11-17

### Added

- Extended custody history validation to pre-enrollment denials and epoch changes, including pending-pledge binding and store-wide authorization ID uniqueness. [PR #45](https://github.com/progentic/Warband/pull/45)

## 0.0.17 - 2026-11-17

### Added

- Added WBRS custody reply codecs with disclosure checks for unauthenticated denials and cursor validation for embedded rejection receipts. [PR #44](https://github.com/progentic/Warband/pull/44)

## 0.0.16 - 2026-11-17

### Added

- Added codecs for all five WBCR custody requests and endpoint-specific role checks using supplied peer credentials. [PR #43](https://github.com/progentic/Warband/pull/43)

## 0.0.15 - 2026-11-17

### Added

- Added single-epoch custody history validation for GENESIS, PENDING and COMMITTED frames, including pledge pairing and published-head checks. [PR #42](https://github.com/progentic/Warband/pull/42)

## 0.0.14 - 2026-11-17

### Added

- Added the `RejectionRecorded` codec with optional event references and producer/stage validation. [PR #41](https://github.com/progentic/Warband/pull/41)

## 0.0.13 - 2026-11-17

### Added

- Added `CapabilityRevoked` and `AttemptDisposition` codecs with golden vectors for revocation, indeterminate attempts and rejected attempts that stop. [PR #40](https://github.com/progentic/Warband/pull/40)

## 0.0.12 - 2026-11-17

### Added

- Added `EvaluationRecorded` and `TransitionAccepted` codecs with checked task-version advancement. [PR #39](https://github.com/progentic/Warband/pull/39)

## 0.0.11 - 2026-11-17

### Added

- Added the `ObservationRecorded` codec and golden vectors for returned and indeterminate outcomes. Decoding checks all four observed bytes against the recorded outcome. [PR #37](https://github.com/progentic/Warband/pull/37)

## 0.0.10 - 2026-11-17

### Added

- Added the `DispatchClaimed` codec and a golden vector linking the claim to the preceding permit and proposal fingerprint. [PR #36](https://github.com/progentic/Warband/pull/36)

## 0.0.9 - 2026-11-16

### Added

- Added the `AuthorizationRecorded` codec with decision-specific validation of capability ID, expiry and use limit for permit, reject and require-approval records. [PR #35](https://github.com/progentic/Warband/pull/35)

## 0.0.8 - 2026-11-16

### Added

- Added the `ProposalRecorded` codec and whole-payload proposal fingerprint. It shares event envelope and digest handling with `TaskCreated`. [PR #34](https://github.com/progentic/Warband/pull/34)

## 0.0.7 - 2026-11-16

### Added

- Integrated all five custody frame kinds through a shared codec with a 1309-byte maximum frame size and support for the existing PENDING and COMMITTED APIs. [PR #33](https://github.com/progentic/Warband/pull/33)

## 0.0.6 - 2026-11-15

### Added

- Added GENESIS, EPOCH and REJECTION payload codecs and hashes, including validation of epoch advancement and denial-receipt fields. [PR #32](https://github.com/progentic/Warband/pull/32)

## 0.0.5 - 2026-11-12

### Added

- Pure recovery classification with focused outcome and mismatch-precedence coverage.

## 0.0.4 - 2026-11-11

### Added

- Pure confirm classification with focused replay and rejection coverage.

### Changed

- Adopted ADR-0008 resource limits and the tracked denial-growth exception.

## 0.1.0-dev.1 - 2026-11-10

### Added

- Pure prepare-request classification for eligible pledges, exact pending replay and explicit scope, sequence, predecessor and pending-conflict rejection, with one focused six-case test and aligned ADR, guidance, inventory and traceability records.

Development source entry only: no release or tag is created. Phase 2 remains incomplete; authentication, link/history validation, custody persistence and runtime replay are not implemented.

## [0.0.2] - 2026-10-18

### Added

- Unpromoted native Ubuntu 26.04 compatibility profile with exact LLVM/Clang/LLD 19.1.7 dependencies, a separately named hosted job and inspectable build/input evidence.

### Changed

- Existing Linux toolchain scripts support explicit profile selection with exact OS, package and compiler-version checks; the original Ubuntu 24.04 and macOS profiles remain unchanged.
- Recorded the candidate's glibc CRT/runtime x86-64-v3 floor and the unexecuted native-profile rejecting cases. Publication of this evaluation does not promote the profile, accept ADR-0006 or select production architecture.

## [0.0.1] - 2026-10-12

### Changed

- Recorded project-owner acceptance of ADR-0007 for scoped Phase 1 E1 composition against the v0.0.0 implementation baseline.
- Aligned decision, engineering, verification and closure references with acceptance and the merged PR #3. Finding closure and overall Phase 1 acceptance remain separate; no application code or tests changed.

## [0.0.0] - 2026-10-12

### Added

- Runtime constitution, accepted initial ADRs, and architecture, contract, engineering, security and verification baselines.
- Repository-scoped agent guidance, governance review skill and ChatGPT project-source instructions.
- Phase 1 Odin CLI with `version` and deterministic 25-byte fixture presentation; no execution authority.
- Phase-aware documentation validation and explicit discovery of two Odin test packages and five named tests, with negative controls.
- Reviewed, pinned Odin source and exact Linux/macOS LLVM profiles, executable architecture checks and build provenance manifests.
- Linux x64 and macOS ARM64 GitHub Actions verification, retained evidence artifacts and protected main with three required checks.
- Project-scoped Lima profiles, including a reviewed x64 verification guest; production architecture remains unset.
- Proposed Phase 1 foundation, hosted-runner compatibility and entrypoint decisions, plus Phase 2 event-integrity design and a closure plan.

### Changed

- The three Phase 1 programs use owner-authorized E1 composition: explicitly scoped High procedures own effects, Mid remains transitively pure and Low cannot call upward or make policy decisions.
- Documentation distinguishes environment-supplied compiler paths from fixed version-query arguments, and validation rejection from interrupted-write preservation. Manifest publication does not establish atomic or crash-safe replacement.
- The engineering standard requires a concrete problem, supporting evidence, coverage gap, expected value and cost for owner review before adding a proposed test.

### Fixed

- CLI argument acquisition and command parsing were coupled; presentation decisions now precede output and process exit.
- Documentation reporting selected validation status; pure decisions now select the result before technical reporting and termination.
- Manifest orchestration mixed JSON parsing, hashing and inspection with decisions; narrow technical helpers and explicit subflows preserve architecture validation before linkage and complete validation before publication.

This initial development version records the foundation verified locally and on
hosted runners. See [entrypoint evidence](docs/verification/phase1-entrypoint-evidence.md)
and [publication evidence](docs/verification/phase1-publication-evidence.md).
ADR-0004 and ADR-0007 remain Proposed with formal ownership and approval pending.
Phase 1 acceptance, dependency recovery and runner compatibility remain separate
governance gates. Phase 2 authority, execution, persistence and production
services are not implemented.

[0.0.2]: https://github.com/progentic/Warband/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/progentic/Warband/compare/v0.0.0...v0.0.1
[0.0.0]: https://github.com/progentic/Warband/tree/v0.0.0
