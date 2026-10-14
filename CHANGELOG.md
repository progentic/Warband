# Changelog

All notable changes to Warband are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Record changes under explicit dated version headings, newest first. Start at
`0.0.0`; Git tags use the `v` prefix. Subsequent version links compare the previous
and current tags. Only include categories that contain notable changes.

## [0.0.2] - 2026-10-13

### Added

- Native Ubuntu 26.04 compatibility candidate with an explicit exact dependency profile, separate hosted job and retained comparison evidence. Promotion and ADR-0006 acceptance require separate owner approval; the required Ubuntu 24.04 profile is unchanged.

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
