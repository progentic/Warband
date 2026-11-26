# Changelog

All notable changes to Warband are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.7 - 2026-11-26

### Added

- Added offline Phase 4 negative-path qualification through synthetic provider replies, including two-request learned-promotion rejection. The grader records separate provider, catalog admission, approval, and post-claim observations and identifies outstanding live and downstream evidence.

## 0.2.6 - 2026-11-25

### Added

- The offline operator workflow now presents the admitted model proposal through the authenticated marker CLI. The runtime retains its original directory descriptor through the decision and verifies the displayed binding before issuing a permit. A receipt lookup with the issued request ID can recover a committed decision without dispatching a worker.

## 0.2.5 - 2026-11-25

### Added

- Added offline qualification of model-request admission from the confined adapter’s validated selection. The runtime checks the returned ID, catalog identity and length against custody-confirmed issuance before admitting the catalog payload.

## 0.2.4 - 2026-11-25

### Added

- Added an offline aggregate qualification runner for the assembled provider stack. It checks the observed request bytes, DNS and kernel traces, typed results and authority-store state, and binds the evidence to the Git tree and binaries.

## 0.2.3 - 2026-11-24

### Added

- Added a one-shot external connector that checks two sets of A and AAAA results for the fixed provider hostname and hands the transport one verified IPv4 socket on port 443. The launcher confines the front end and transport with separate network namespaces and kernel syscall filters.

## 0.2.2 - 2026-11-24

### Added

- Added the one-shot Odin launcher, isolated front end and libcurl transport for fixture-driven provider calls. The Linux qualification script identifies the linked library, TLS backend and trust configuration and grades request counts, deadlines, cancellation, issuer loss and response limits on x64-review.

## 0.2.1 - 2026-11-24

### Added

- Added `tests/integration/linux/test_provider_transport.py` to count HTTP requests independently of TCP connections and grade duplicate handoff, cancellation, stall, redirect, proxy and lost-reply cases against a synthetic TLS endpoint.

## 0.1.7 - 2026-11-23

### Added

- Added live marker observation, independent evaluation and atomic acceptance. Exact normal and lost-reply effects advance once from **1/2** to **2/3**; absent, conflicting and unassessed outcomes remain incomplete without automatic redispatch. [Completion qualification](docs/verification/traceability-matrix.md#live-marker-completion)

## 0.1.6 - 2026-11-23

### Added

- Added a confined Linux marker worker and trusted exclusive-create broker. The matching-kernel harness verifies identity separation, cgroup and seccomp enforcement, bounded time, memory and output, exact creation, independent occupancy refusal and zero automatic retries after uncertain execution. [Worker qualification](docs/verification/traceability-matrix.md#confined-marker-worker)

## 0.1.5 - 2026-11-23

### Added

- Added a Linux marker gate that confirms the single-use claim and rechecks the offered request against its approval before broker handoff. A changed payload produces a custody-confirmed refusal. [WB-NEG-008 evidence](docs/verification/traceability-matrix.md#post-claim-marker-gate)

## 0.1.4 - 2026-11-23

### Added

- Added Linux CLI approval for a confirmed marker proposal. An exact operator approval can issue one permit. Receipt lookup returns the original decision after a lost reply. [Procedure and qualification](docs/engineering/phase3-entry-review.md#review-a-marker-proposal)

## 0.1.3 - 2026-11-23

### Added

- Activated Phase 3 Linux marker intake. The runtime provisions a private attempt directory and confirms the task and normalized proposal through custody before reporting the proposal binding. [Qualification](docs/verification/traceability-matrix.md#confirmed-marker-proposal-intake)

## 0.1.2 - 2026-11-22

### Added

- Added a pure marker-chain replay reader that checks recorded approvals, independently verifies observation verdicts, and advances task state only for a custody-confirmed acceptance. [Replay qualification](docs/verification/traceability-matrix.md#marker-chain-replay)

## 0.1.1 - 2026-11-22

### Added

- Added portable codecs for marker permits, claims, observations, evaluations and accepted transitions. [Wire-format qualification](docs/verification/traceability-matrix.md#marker-evidence-codec-qualification)

## 0.1.0 - 2026-11-22

### Changed

- Proto (Ian) adopted v0.1.0 at Phase 2 exit commit `a975149`. This release qualifies the no-op authority core, including exactly-once state acceptance and replay from custody-confirmed history, within the measured preproduction envelope. [Tagged exit record](https://github.com/progentic/Warband/blob/v0.1.0/docs/governance/phase2-exit.md)

## 0.0.57 - 2026-11-22

### Added

- Added portable marker proposal and approval codecs and a pure check that binds a recorded affirmative decision to its exact proposal. [Codec qualification](docs/decisions/0009-controlled-local-marker-execution.md#proposal-and-approval-codec-qualification)

## 0.0.56 - 2026-11-22

### Added

- Recorded bounded Phase 2 exit against the tested no-op core, with scoped traceability, runner-label disposition and administrative expiry of WB-EXC-001. [Phase 2 exit](docs/governance/phase2-exit.md)

## 0.0.55 - 2026-11-22

### Added

- Qualified receipt recovery after the filesystem returned EIO on the SQLite WAL commit sync. The importer withheld acknowledgment and recovered the captured event with one custody confirmation. [PR #94](https://github.com/progentic/Warband/pull/94)

## 0.0.54 - 2026-11-22
=======
## 0.1.0 - 2026-11-10

### Added

- Pure prepare-request classification for eligible pledges, exact pending replay and explicit scope, sequence, predecessor and pending-conflict rejection, with one focused six-case test and aligned ADR, guidance, inventory and traceability records.

## 0.0.3 - 2026-11-11

### Fixed

- Reconciled governance and phase status with recorded acceptance, authorized pure-code slices and Ubuntu rejection evidence.

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


[0.1.0]: https://github.com/progentic/Warband/compare/v0.1.0...v0.0.3
[0.0.3]: https://github.com/progentic/Warband/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/progentic/Warband/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/progentic/Warband/compare/v0.0.0...v0.0.1
[0.0.0]: https://github.com/progentic/Warband/tree/v0.0.0
