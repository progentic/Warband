# Phase 1 closure plan

Warband's foundation is technically verified locally on Linux x64 and macOS ARM64. Formal Phase 1 acceptance and hosted enforcement remain pending. This plan records the remaining work; it does not authorize commits, remotes, account selection, pushes, infrastructure creation, workflow changes, or ADR acceptance.

On 2026-10-10 the user selected [progentic/Warband](https://github.com/progentic/Warband) and subsequently authorized committing and pushing the current Phase 1 status to `main`. Its HTTPS URL is configured as this folder's `origin`. Existing authentication is used; no account was switched. ADR ownership and formal approval remain pending. [Local evidence](../verification/phase1-review-evidence.md) remains the source for actual command results. [ADR-0004](../decisions/0004-reproducible-odin-toolchain-and-ci.md) stays Proposed. ADR-0005 design may proceed as Proposed, independently of Phase 2 implementation authorization.

## Gate 1 Review the source baseline

Before staging, confirm the Git top level is exactly `/Users/godzilla/Documents/Projects/Warband`. Review the complete prospective file inventory and differences against the immutable bootstrap and selected remote baseline. The local branch now starts at the remote initial commit. Most foundation files are still new, so ordinary unstaged `git diff` alone cannot review them.

The remote already has `main` at `c2bb2919e2366f7d27d9f3036947bdb7df618ae8` (Initial commit), containing `.gitignore`, `LICENSE`, and `README.md`. These files were inspected through GitHub and compared with the local files. The remote README is a short placeholder and its ignore rules target Rust. On 2026-10-10 the user directed adoption of the remote BSD 3-Clause license, copyright 2026 Proto. The active root LICENSE was replaced byte-for-byte with remote Git blob `6e0dd6167e4717f43f97d29904779b28bfa4b53e`. The retained original bootstrap snapshot remains unchanged.

The remote initial commit was fetched and adopted as the local branch/index baseline using a mixed reset, preserving working files. The foundation commit will retain that commit as an ancestor. Refresh the remote reference before publication; do not force-push or replace existing history.

Include root project guidance, license, active documents, `.agents/skills/`, workflows, source, tests, toolchain lock, and VM recipes. Exclude `.local/`, `out/`, `build/`, interpreter caches, ZIP attachments, and the original extracted bootstrap. Preserve those input/evidence files locally.

The root-scoped `/planning/` ignore excludes historical context linked to the ignored bootstrap. Including these notes in a fresh repository checkout would cause broken links. Keep them local; move any still-needed decisions into active documents rather than publishing duplicate governance.

Produce a sorted prospective-commit manifest with path, size, mode, and SHA-256. Inspect each file for unintended binaries, secrets, generated state, source references outside the baseline, and unexplained modifications. Verify the constitution, accepted ADRs 0001–0003, invariant definitions, and earlier negative-path semantics remain preserved.

Run governance, Python controls, explicit Odin package discovery, native build/test/smoke, actionlint, and shellcheck against a source-only checkout without ignored input directories. Link real Linux evidence to the exact reviewed source tree. Record outstanding structural findings rather than converting technical test passes into general architecture approval.

The user has authorized staging, committing, and pushing the current foundation. Review the concrete inventory/diff and available verification before doing so. This authorization does not accept ADRs, configure branch enforcement, or authorize Phase 2.

### Structural findings for the approval review

Technical test passes do not resolve every literal procedure-layering requirement. The documentation-only pass records these existing mismatches without changing application code:

- [High] `cmd/warband/main.odin` `main()` L21 calls `read_command()` directly -> orchestration reaches argument parsing rather than calling only Mid decisions.
- [High] `scripts/check_docs.py` `main()` L13 and L15 calls inventory loading and presentation -> orchestration crosses directly into filesystem/parsing/reporting boundaries.
- [High] `scripts/build_manifest.py` `main()` L18 reads/parses JSON and L28 hashes executable bytes alongside architecture validation -> the entry function mixes technical operations with decisions and exceeds the High size limit.

These are concrete instances of the already recorded effect-dispatch/layering question. A review must choose a compliant boundary arrangement or explicitly approve revised guidance before claiming complete structural compliance. Do not label I/O wrappers pure domain functions or silently accept an exception through ADR-0004. Publication of the current foundation does not resolve these findings or claim structural approval.

## Gate 2 Select and connect the hosted repository

Repository selection and remote configuration are complete: `origin` is `https://github.com/progentic/Warband.git`, the repository is public, and its default branch is `main`. GitHub reported push/admin permissions for the existing authentication. The user separately authorized commit/push; enforcement configuration, account plan, and collaborator policy remain pending. Do not switch authentication implicitly.

After authorization, integrate the reviewed foundation onto the existing remote history and push the resulting commit. Run the complete Phase 1 workflow at that commit. Preserve stable checks: Documentation Governance / validate, Phase 1 Linux Foundation, and Phase 1 macOS Portability. Primary Linux compiler/build/test jobs remain on `ubuntu-latest`; retain the Ubuntu 24.04 guard and reject unexpected OS changes. A moving runner label does not freeze dependency inputs.

## Gate 3 Preserve actual CI evidence

The current workflow only writes a success summary. Before the hosted run, prepare a separately reviewed workflow change to capture compiler, build, governance, test, and smoke output into platform-specific `out/` logs. Set `shell: bash` explicitly so logging through `tee` keeps fail-fast and pipefail behavior. Verify a failing producer cannot turn into a successful pipeline.

Upload only the platform `out/` evidence directory after success or failure, using a reviewed full action SHA and `if: always()`. Exclude hidden files, source credentials, `.git`, `.local`, VM state, and provider data. Use unique artifact names containing platform, tested source SHA, and run attempt. A missing initialized evidence directory should fail the upload; checkout/setup infrastructure failures may have only native Actions logs.

The public official upload-artifact v4.6.2 commit inspected for this plan is `ea165f8d65b6e75b540449e92b4886f43607fa02`. It is a planned dependency, not installed or configured by this documentation pass. Recheck its suitability when making the workflow change.

Retain source/workflow SHA, resolved runner image/version, Odin SHA and report, LLVM/C++ versions, exact package receipts, build flags, binary SHA-256 and architecture/linkage, complete test identities/counts, and failed-stage logs. Artifact retention must fit repository policy; propose 30 days for routine run evidence and export acceptance evidence into a durable maintainer-controlled archive. A successful upload is not proof the tests passed. PR artifacts remain untrusted data and must not be executed or deployed by a privileged follow-up job.

## Gate 4 Define dependency retention and recovery

Exact Ubuntu package revisions can disappear from current mirrors. Continue failing closed when the locked revision is unavailable. Do not substitute another LLVM 19 patch, add a new repository silently, disable package signatures/hash checks, or remove the OS guard.

Propose a maintainer-owned dependency archive containing the complete transitive package set, original signed release/index metadata, exact revisions/architectures, upstream URIs, SHA-256 manifests, and the tested Odin source revision. Retain the reviewed Homebrew bottle plus its digest and required native dependency versions. Select archive custody/storage and retention during governance review; no external archive exists yet.

Validate recovery in a clean matching guest with empty caches: verify provenance/signatures and every package digest, install the exact locked toolchain, assert actual versions, rebuild Odin/Warband, and rerun the full gate. Retention is not complete until this restore test succeeds.

Ubuntu's official snapshot service is an alternative recovery source. A concrete snapshot must be reviewed and tested for the exact package revisions and dependency closure before use. Keep signature, hash, and metadata validity checks; an unavailable or unverifiable snapshot blocks the build. An archive/snapshot change needs recorded provenance and approval, not an automatic fallback. Retain old lock inputs until a reviewed replacement has passed both platform gates, plus an owner-approved recovery period.

## Gate 5 Close governance and enforce checks

Assign a responsible ADR-0004 owner and reviewer. Review implementation evidence, the source baseline, hosted results, dependency retention/recovery, and unresolved procedure-layering concerns. Record approval separately from technical results. Change Proposed to Accepted only after explicit governance approval and the associated documentation/traceability review; no owner or acceptance is inferred here.

Configure supported branch protection/rulesets only after the account/repository/plan is known and the actual named jobs have run. Require the observed checks and appropriate review for source, contracts, toolchain, and workflow changes. Inspect the effective settings and prove an unpassing change cannot merge through the intended path. Document unsupported controls instead of claiming enforcement.

## Gate 6 Prepare Phase 2 design

[ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md) is a Proposed design draft. It addresses event encoding, anchors, evidence provenance, transactional acceptance, capability consumption, uncertain execution outcomes, and deterministic replay. Its open decisions and verification matrix must be reviewed before any Phase 2 code is authorized.

No general agent orchestration, provider integration, new execution surface, distributed consensus, or production deployment belongs to this closure plan. Phase 1 acceptance does not itself authorize Phase 2 implementation.

## Current gate status

| Gate | Current disposition |
|---|---|
| Local technical foundation | PASS; previously recorded Linux and macOS evidence |
| Source baseline review and foundation commit | Commit/push authorized; license aligned; existing remote history adopted; publication verification in progress |
| Repository connection | Configured and verified; existing authentication unchanged |
| Hosted runs | Pending publication and actual workflow results |
| Evidence upload and dependency recovery | Plan prepared; workflow/archive changes and restore test pending |
| Owner assignment, ADR acceptance, enforced required checks | Deferred by the user |
| ADR-0005 design | Proposed draft only |
| Phase 2 implementation | Not authorized |

References: [GitHub shell failure semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), [artifact behavior](https://github.com/actions/upload-artifact/tree/ea165f8d65b6e75b540449e92b4886f43607fa02), and [Ubuntu snapshot service](https://snapshot.ubuntu.com/).
