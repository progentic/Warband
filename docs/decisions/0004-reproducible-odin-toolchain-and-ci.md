# ADR-0004: Reproducible Odin Toolchain and CI Verification

- **Status:** Proposed
- **Date:** 2026-10-10
- **Decision owner:** Unassigned; must be assigned during governance review
- **Scope:** Warband Phase 1 foundation; later phases consume the same verification contract
- **Supersedes:** None
- **Related decisions:** Existing accepted ADR-0001 through ADR-0003 (unchanged)
- **Authority:** Proposal for review. The accompanying agent directive authorizes local Phase 1 work; it does not imply formal acceptance of this ADR or of unresolved constitutional decisions.

## Context

Warband begins as a deterministic Odin command-line runtime. Its Linux deployment must eventually demonstrate that untrusted proposals cannot bypass runtime policy, execution authority, evidence-based acceptance, or replay. Before implementing these guarantees, the project needs a build and verification environment with known inputs and credible failure behavior.

The supplied documents-only bootstrap is in Phase 0. `scripts/check_docs.py` previously passed on the developer's local Python interpreter, but this does not validate runtime code. Existing constitutional requirements and accepted ADRs govern changes. GitHub repository ownership, remote, visibility, and production architecture have not been selected. The host is Apple Silicon macOS with Homebrew-managed Lima, Colima, and QEMU available. Local Linux security controls must be validated under Linux.

GitHub Actions shall compile the official Odin compiler from source, rather than assuming the runner's compiler or a floating Homebrew build is the project toolchain. GitHub documents `ubuntu-latest` as an x64 Ubuntu virtual machine runner, while `ubuntu-slim` is a low-resource container runner intended for lightweight automation, not heavyweight compiler and integration builds. Neither label pins an immutable runner image.

## Decision

### D1. Primary Linux build and test runner

1. Use GitHub-hosted `runs-on: ubuntu-latest` for the primary **x64** Odin compiler build, Warband build, phase-applicable negative tests, invariant tests, Linux integration/replay tests, and release smoke tests.
2. Do **not** use `ubuntu-slim` for these jobs. A lightweight documentation-only job may use an appropriate runner independently, but must not become a substitute for Linux runtime validation.
3. Treat `ubuntu-latest` as a moving hosted image. Record the resolved image/version in CI evidence. A release reproducibility requirement may later justify an explicitly versioned runner or controlled build image; do not pretend that the moving label provides a fixed operating system.
4. When native Linux ARM64 coverage is required, add a separate `ubuntu-24.04-arm` job (or another reviewed ARM64 label). `ubuntu-latest` cannot certify ARM64. The production release architecture remains undecided; do not infer it from the primary CI runner.
5. Add a macOS ARM64 portability job once runtime code exists. Passing macOS tests provides no evidence that Linux sandbox controls work.

### D2. Build the official Odin compiler from reviewed source

1. Obtain Odin from the official `odin-lang/Odin` upstream repository at a **reviewed full commit SHA**, verify the checked out `HEAD` matches exactly, and record the SHA in a project-owned toolchain lock/configuration file. Do not use `master`, floating release tags, short hashes, or an unspecified Homebrew package as CI source authority.
2. Select and pin a compatible major LLVM version and explicit tool locations as required by that Odin revision. Install the matching C/C++ compiler, LLVM headers/libraries, and linker dependencies on the Linux runner. Do not rely on macOS Homebrew libraries for Linux linkage. Record toolchain versions, package provenance where feasible, and configuration inputs.
3. Build the compiler from source using the build procedure at that pinned revision, with `LLVM_CONFIG` set explicitly when needed. Capture and verify `odin version` and `odin report`. Keep the Odin compiler alongside, or configured to locate, its matching `base`, `core`, and `vendor` tree. Put this compiler first on the job `PATH` and assert the resolved executable is the built one.
4. Do not execute unreviewed remote installer scripts merely to obtain compiler dependencies. If an additional package repository is necessary, document and review the trust and versioning implications.
5. A compiler failure, unsupported LLVM mismatch, checksum/revision mismatch, or failure to resolve the pinned compiler shall fail the required job; never silently fall back to the host-installed version.

### D3. Build Warband and prove target identity

1. Build the explicit Warband command entry package with `odin build`. Use distinct output and cache paths for `linux_amd64`, `linux_arm64`, and `darwin_arm64`; no cross-platform object reuse.
2. Assert the runner/guest architecture, Odin target, compiled executable format, and machine architecture. On Linux, inspect the generated ELF (for example with `file` and `readelf`); on macOS, inspect the Mach-O. The primary `ubuntu-latest` artifact must be an x86-64 Linux executable.
3. Persist a concise build manifest containing Odin SHA/version, LLVM details, runner image, build flags, executable checksum, architecture, and dependency linkage information. Use this for evidence; it is not a second runtime event ledger.
4. Do not publish a production release for an architecture that has not been selected and validated on a matching target.

### D4. Canonical verification sequence and completeness

The required Phase 1 pipeline is ordered as follows. Separate jobs may run independently where their dependencies and required status checks remain explicit:

1. Check out Warband and pinned official Odin source.
2. Install reviewed compatible LLVM/C++ dependencies; build and verify Odin.
3. Build Warband; assert executable architecture and toolchain provenance.
4. Run `python3 scripts/check_docs.py` with the new **phase-aware** document validator.
5. Run a committed, explicit Odin test package manifest. Run every applicable negative-path and invariant test, plus integration/replay and smoke suites when those suites exist in the current phase.
6. Produce a readable evidence summary and fail the required check on any applicable missing, skipped, failed, or unexpectedly absent suite.

The manifest must enumerate actual test packages, not rely on `odin test -all-packages` to discover unimported directories. Verification must compare expected packages with the repository's declared test inventory; enforce an expected test count using a reliable, documented mechanism supported by the pinned compiler/tooling. A deleted or omitted test package must not produce a green result simply because some other package ran. Tests planned for Phases 2–5 remain **deferred**, not passing and not silently skipped. Add a focused negative control proving the inventory/count gate fails when a required package is omitted.

Phase 1 tests must establish real behavior for phase-built code. Do not create placeholder or tautological tests to satisfy a numerical quota.

### D5. Phase-aware governance and package boundaries

1. Preserve the constitution, accepted ADR-0001 through ADR-0003, existing invariant/negative-path IDs, and their meaning. Inspect actual repository filenames and conventions before editing; place this ADR beside the current decision records.
2. Extend `scripts/check_docs.py` to recognize an explicit, validated project phase. Unknown or malformed phases are errors. Phase 0 continues to reject premature `src/` and `cmd/` material; Phase 1 permits them under documented conditions. Do not bypass established documentation or traceability checks.
3. Keep the validator small, standard-library-only, and organized so orchestration, document rules, and filesystem/parsing operations are distinct. Report errors clearly without swallowing failures.
4. Document the three procedure levels without conflating code organization with a security boundary. Pure policy/evaluation/transition functions must not receive database, filesystem, or process handles. The actual runtime trust boundaries will require Linux enforcement in later phases.
5. Add minimal Phase 1 source only: explicit entry package, typed identifiers/errors, canonical fixtures/serialization primitives, deterministic clocks/IDs, and verification scaffolding. Do not implement Phase 2 execution or accept its invariants as satisfied.

### D6. Local development and VM boundary

1. Keep all project code, VM recipe/provisioning inputs, generated state and caches under the Warband project or an explicitly project-scoped location. Exclude disposable VM state and build outputs from Git. Do not mount the host home directory by default.
2. Use installed Homebrew-managed Lima for a proposed full Linux development guest. An ARM64 VZ guest on Apple Silicon is a reasonable **development** selection, not a production ABI decision. Record a reviewed guest image digest and guest architecture before provisioning a VM. Use a separate full x86-64 QEMU guest only when local x86-64 kernel behavior needs testing; do not confuse user-mode translation with a full x86-64 guest.
3. No runtime keys, provider credentials, public listener, production storage, or privileged production service is needed in Phase 1.
4. Keep a portable native macOS test path for platform-independent logic. Security claims that depend on Linux must be validated in Linux.

### D7. GitHub Actions security and repository control

1. Start from GitHub's supplied workflow YAML structure where applicable, then install the project-owned Odin build/test commands.
2. Pin third-party and GitHub-provided actions by **reviewed full commit SHA**; do not use floating tags for actions in required workflows. Use `permissions: contents: read` or narrower, and prevent persistence of checkout credentials unless explicitly necessary.
3. Run untrusted pull requests using `pull_request` jobs with no deployment secrets, elevated tokens, privileged `pull_request_target` checkout flows, or access to production machines. **Never run untrusted PR workloads on the production VM.**
4. Maintain stable named required jobs/checks as they are split. Configure branch protections/rulesets only after repository owner, visibility, plan and access are confirmed. If controls are unavailable, document the gap rather than assert enforcement.
5. The Warband Git remote remains unset. No GitHub repository creation, account switching, remote write, push, deployment, or secret provisioning is authorized by this ADR.

## Rejected alternatives

- **Use `ubuntu-slim` for all work:** rejected because resource and execution limitations do not fit compiler and kernel-sensitive integration workloads.
- **Use only an installed or floating Odin binary:** rejected because version drift obscures compiler provenance.
- **Use only `odin test -all-packages`:** rejected because an unimported test package can be omitted from execution.
- **Treat macOS or user-mode translated execution as Linux isolation evidence:** rejected because host kernel enforcement differs.
- **Pin the production architecture now:** deferred pending a deployment decision. The primary x64 hosted CI selection does not make that decision.
- **Add generic provider or agent orchestration now:** rejected for Phase 1 because it does not improve the first deterministic acceptance proof.

## Consequences and limitations

- CI has a compiler build cost and may require reviewing LLVM binary/library compatibility when Odin changes.
- A full source SHA and selected LLVM version reduce uncontrolled toolchain drift, but hosted image updates and package repository changes remain. Build records expose this residual variation; strict bitwise reproducibility is not claimed.
- GitHub checks cannot be reported as remotely passing until the repository is connected and Actions actually runs them. Local YAML validation is not cloud execution evidence.
- Phase 1 infrastructure checks are not proof of proposal isolation, audit acceptance, or replay; those claims belong to later implementation gates.
- If an external LLVM repository is needed, its trust, artifact hashes, availability, and retention should be documented instead of concealed by a generic installation command.

## Phase 1 acceptance criteria

All criteria must be demonstrated or explicitly marked blocked; no invented pass status.

- [ ] Phase 0 bootstrap inventory and existing decisions compared without destructive overwrite; ADR-0004 added as **Proposed**.
- [ ] Unknown phase rejected; Phase 0 restrictions retained; Phase 1 source directories permitted only under the declared phase.
- [ ] Odin SHA and compatible LLVM/build inputs committed to a readable project toolchain lock, with independent version/identity checks.
- [ ] Clean x64 Linux checkout builds Odin from source, builds Warband with the intended compiler, and verifies x86-64 ELF architecture.
- [ ] Phase-relevant negative and domain tests run from an explicit manifest; omission or wrong count makes verification fail.
- [ ] Stable Linux CI job with `ubuntu-latest`, pinned actions, read-only token, and safe PR trigger is present. No heavy job uses `ubuntu-slim`.
- [ ] macOS portability checks execute when runtime code is present, or are precisely reported as unverified/blocked.
- [ ] Project-scoped Lima recipe has explicit mounts and architecture; VM provisioning remains blocked until guest image/digest and architecture have been reviewed.
- [ ] Documentation, contracts, execution pipeline, negative paths, package boundary mapping, and traceability reflect the work actually completed. Deferred Phase 2–5 requirements remain deferred.
- [ ] Build/test commands, outcomes, environment versions, architecture assertions, and known gaps are recorded; no status is marked passed without its evidence.
- [ ] A responsible owner and applicable Phase 0 governance gate are identified before declaring formal Phase 1 completion.

## Follow-on decisions

Separate proposed ADRs are required for event canonicalization/hash anchors, transaction and crash recovery, capability and approval semantics, Linux worker isolation, and effect dispatch/procedure layering where existing accepted decisions do not already settle them. No such decision is silently accepted through this CI ADR.

## References

- GitHub-hosted runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- GitHub Actions secure use: https://docs.github.com/en/actions/reference/security/secure-use
- Safe pull request workflows: https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target
- GitHub workflow syntax and token permissions: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Odin upstream: https://github.com/odin-lang/Odin
- Odin installation/build prerequisites: https://odin-lang.org/docs/install/
- Lima architecture documentation: https://lima-vm.io/docs/config/multi-arch/

**Verification note (2026-10-10):** Upstream's then-current `build_odin.sh` reported LLVM 17–22 as supported. The selected pinned Odin commit, rather than this observation about a moving branch, governs the real Phase 1 dependency choice.

## Proposed verification correction dated 2026 10 10

The initial implementation incorrectly applied the native macOS LLVM 19.1.7 pin to Ubuntu Noble's standard repositories. The revised lock uses exact platform profiles: Linux LLVM/clang 19.1.1 from signed Ubuntu Noble repositories, and native macOS LLVM/clang 19.1.7 from the reviewed Homebrew bottle. Linux clang-19, llvm-19-dev, and lld-19 use Debian revision `1:19.1.1-1ubuntu1~24.04.2`. Both compiler components must match their exact platform versions; a different patch version fails validation.

The primary CI runner remains `ubuntu-latest`. Linux installation explicitly checks Ubuntu 24.04 and fails on an unreviewed runner OS change. Package URIs, installed revisions, and build metadata retain the actual dependency provenance. Native and Linux verification are separate, and hosted CI execution still requires an authorized repository connection.

This correction remains part of the Proposed decision. It does not assign ownership, accept ADR-0004, select production architecture, or implement the future event encoding/acceptance/recovery/replay decision. See `docs/verification/phase1-review-evidence.md` for current results.
