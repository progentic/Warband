# Warband: Phase 1 Agent Execution Directive

**Date:** 2026-10-10

**Companion:** ADR-0004, *Reproducible Odin Toolchain and CI Verification* (status: Proposed)

**Working tree:** `/Users/godzilla/Documents/Projects/Warband`
**Initial state reported:** isolated local Git repository on `main`, no commits, no remote; reviewed bootstrap at `../warband-docs-bootstrap-v2/`.

## Mission

Start the smallest useful Phase 1 implementation of Warband: a reproducible Odin command-line build, phase-aware governance checks, a project-scoped Linux VM recipe, and secure GitHub Actions YAML with complete negative-path test discovery. Produce demonstrated local evidence. Do not implement the Phase 2 no-op acceptance pipeline yet.

The user authorizes **local Phase 1 work** by this directive. The companion ADR is **Proposed**, not accepted. Keep acceptance and unresolved owner/governance gates visible; do not rewrite prior accepted decisions to make the work appear approved.

## Hard constraints

- Operate only inside the specified Warband project. Before every repository operation, confirm the Git top level is that exact directory; do not fall through to an unrelated parent/home repository.
- Inspect the existing tree, the actual constitution, accepted ADR-0001 through ADR-0003, contracts, validator, and traceability **before** copying or changing anything. If ADR-0004 already exists, stop collision and use the next free ADR ID with an explicit report. Place the supplied ADR in the repository's existing ADR directory/naming convention.
- Preserve accepted invariants and WB-NEG-001 through WB-NEG-012 IDs; extend without renumbering. Do not claim Phase 2 requirements are implemented.
- If the bootstrap must be imported, copy its contents to the repository root without an extra enclosing directory. Compare existing files first; never blindly overwrite local work. The original bootstrap must remain unchanged.
- Do not select a GitHub account, configure a remote, create a repository, push, deploy, use provider secrets, or commit changes without separate authorization. Do not run untrusted PR code on the production VM.
- Use built-in language tools and standard-library-only Python governance scripts. Add only necessary dependencies, code, and tests. Avoid placeholder tests and general purpose abstractions.
- Do not claim an operation or test passed until its output has been inspected. If an environment, tool, or permission blocks a gate, provide precise partial evidence and the missing prerequisite.

## Execute in this order

### 1. Baseline and decision integration

- Confirm directory isolation and inventory files. Run the unchanged baseline documentation validator and retain its result.
- Import the reviewed bootstrap safely if it is not already the working tree. Keep all prior accepted ADR text untouched.
- Add ADR-0004 with `Status: Proposed`, referencing the other accepted ADRs. Add an explicit owner/review status, without pretending an owner has been assigned.
- Update phase and verification documentation and traceability to reflect only changes actually implemented. Propose other ADRs rather than deciding authority/recovery/integrity issues inside this Phase 1 task.

### 2. Phase-aware governance validator

- Replace the unconditional prohibition on `src/` and `cmd/` with a documented explicit phase value. Phase 0 continues to prohibit runtime code; Phase 1 permits the initial source tree. Unknown/malformed phases must fail closed.
- Separate validator orchestration, document rules, and low-level filesystem/parse helpers without a speculative framework.
- Validate real examples for allowed Phase 0, allowed Phase 1, invalid phase, and attempts to bypass mandatory document requirements. Preserve earlier negative checks.

### 3. Pin and build Odin on Linux

- Choose a reviewed, real **full Odin source SHA** from official `odin-lang/Odin`. Record it and its provenance in a project-owned lock/config file; do not invent a SHA or derive it from the local Homebrew version alone.
- Verify the pinned Odin revision's build script and determine the supported LLVM version. Pin compatible LLVM and C/C++ build prerequisites. Record how each tool/version is obtained and verified; do not execute unreviewed download-to-shell scripts.
- Check out the exact source SHA, verify `HEAD`, build Odin from source, and prove that this compiler is the one used for Warband. Keep the correct Odin `base`, `core`, and `vendor` paths available (or explicitly configure `ODIN_ROOT`).
- Add the smallest executable Warband command package and minimal domain identifiers/errors and deterministic fixtures needed for meaningful Phase 1 verification. Build into `out/linux_amd64` (or the established equivalent) and assert ELF x86-64 identity on `ubuntu-latest`. Distinguish all Linux and macOS outputs/caches.

### 4. Make CI enforce the contract

- Use GitHub-hosted `runs-on: ubuntu-latest` for compiler, Warband build, Phase 1 negative/invariant suites, and later Linux integration/replay and release smoke jobs. Do not use `ubuntu-slim` for these jobs.
- Start from the existing docs workflow and GitHub's normal YAML structure. Pin `actions/checkout` and other external actions to reviewed full commit SHAs. Use least-privilege `GITHUB_TOKEN`, `persist-credentials: false`, and unprivileged `pull_request` / `push` triggers. Never combine elevated `pull_request_target` permissions with untrusted checkout/execution.
- Run, in order: checkout; pinned Odin build and identity assertion; Warband build/architecture assertion; `python3 scripts/check_docs.py`; explicit Odin test packages; phase-applicable negative/invariant/integration/replay/smoke verification. A failure anywhere needed for a required check must stop that check.
- Create a repository file manifest listing test packages (leave it uncommitted until authorized). Ensure every listed package ran; compare manifest with the declared package inventory and reliably assert expected test counts. Add a focused negative control showing that removing a required package fails the check. Do not treat Phase 2+ absent suites as passed.
- Preserve stable required job names. Do not claim cloud checks are enforced until remote configuration and a real Actions run exist. Add macOS portability validation once applicable code exists.

### 5. Prepare local Linux VM without widening scope

- Create a minimal Lima recipe and provisioning record under the project. Disable default home mounts; mount only this project as necessary; keep disposable state/caches project-scoped and ignored by Git.
- Record development guest architecture and reviewed image digest before provisioning. ARM64 VZ is a reasonable local development choice on Apple Silicon, but this is not a production architecture decision. Do not create the VM until that selection is complete.
- No exposed public ports, provider credentials, runtime accounts, or production service needed.

### 6. Verify and report

Run the baseline docs check, updated phase-aware validator checks, clean local applicable builds, Odin vet and behavioral tests, test-manifest completeness negative control, architecture assertions, and YAML syntax/permission inspection. Use cloud evidence only if a remote and Actions are separately authorized. Review the diff for scope expansion, unneeded tests, ignored failures, accidental secrets, and any bypassed invariant.

Do not replace a failed platform check with a fabricated PASS or a macOS success. Record proof for Linux and macOS separately. If the local Linux guest is not selected/provisioned, a successful Linux GitHub-hosted build may prove the build but does not prove local VM readiness.

## Required final handoff

Provide:

1. **Changed files:** paths and one sentence per meaningful change.
2. **Commands and results:** exact successful/failing commands, compiler SHA/LLVM versions, tested platform, artifact architecture, package inventory and test counts.
3. **Security and governance:** which existing invariants/contracts remained unchanged, what documentation changed, validator bypass checks, and which obligations are deferred.
4. **Known gaps:** missing owner, unselected release architecture, VM image/digest or provisioning, absent GitHub remote/cloud execution, and the consequences for the Phase 1 completion claim.
5. **Diff review:** unnecessary code/tests, disabled checks, broad permissions, credential persistence, unsafe mounts, or other boundary violations; explicitly state whether found and corrected.
6. **Gate outcome:** `PASS`, `FAIL`, or `BLOCKED` per acceptance criterion, with evidence. Do **not** declare Phase 1 formally complete while its governance gate is unmet.

**Definition of success for this execution:** the first real, narrow Phase 1 implementation is present and verifiable, with all work remaining inside the Warband repository, and with no false implication that Phase 2 runtime authority or production deployment is complete.
