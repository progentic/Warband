# Phase 1 closure plan

Warband's foundation is technically verified locally on Linux x64 and macOS ARM64. Formal Phase 1 acceptance and hosted enforcement remain pending. This plan records the remaining work; it does not authorize commits, remotes, account selection, pushes, infrastructure creation, workflow changes, or ADR acceptance.

On 2026-10-10 the user selected [progentic/Warband](https://github.com/progentic/Warband) and subsequently authorized committing and pushing the current Phase 1 status to `main`. Its HTTPS URL is configured as this folder's `origin`. Existing authentication is used; no account was switched. ADR ownership and formal approval remain pending. [Local evidence](../verification/phase1-review-evidence.md) remains the source for actual command results. [ADR-0004](../decisions/0004-reproducible-odin-toolchain-and-ci.md) stays Proposed. ADR-0005 design may proceed as Proposed, independently of Phase 2 implementation authorization.

## Gate 1 Review the source baseline

Before staging, confirm the Git top level is exactly `/Users/godzilla/Documents/Projects/Warband`. The initial publication review included a complete prospective inventory because the foundation files were then untracked. For subsequent changes, inspect the complete diff against the published main baseline and preserve the immutable bootstrap and accepted decisions.

The remote already has `main` at `c2bb2919e2366f7d27d9f3036947bdb7df618ae8` (Initial commit), containing `.gitignore`, `LICENSE`, and `README.md`. These files were inspected through GitHub and compared with the local files. The remote README is a short placeholder and its ignore rules target Rust. On 2026-10-10 the user directed adoption of the remote BSD 3-Clause license, copyright 2026 Proto. The active root LICENSE was replaced byte-for-byte with remote Git blob `6e0dd6167e4717f43f97d29904779b28bfa4b53e`. The retained original bootstrap snapshot remains unchanged.

The remote initial commit was fetched and adopted as the local branch/index baseline using a mixed reset, preserving working files. Foundation commit `53415e7853b598bc341bc651df2edc694b9afe7e` was pushed to `main` as a fast-forward, retaining that initial commit as its parent. Do not force-push or replace existing history.

Include root project guidance, license, active documents, `.agents/skills/`, workflows, source, tests, toolchain lock, and VM recipes. Exclude `.local/`, `out/`, `build/`, interpreter caches, ZIP attachments, and the original extracted bootstrap. Preserve those input/evidence files locally.

The root-scoped `/planning/` ignore excludes historical context linked to the ignored bootstrap. Including these notes in a fresh repository checkout would cause broken links. Keep them local; move any still-needed decisions into active documents rather than publishing duplicate governance.

Produce a sorted prospective-commit manifest with path, size, mode, and SHA-256. Inspect each file for unintended binaries, secrets, generated state, source references outside the baseline, and unexplained modifications. Verify the constitution, accepted ADRs 0001–0003, invariant definitions, and earlier negative-path semantics remain preserved.

Run governance, Python controls, explicit Odin package discovery, native build/test/smoke, actionlint, and shellcheck against a source-only checkout without ignored input directories. Link real Linux evidence to the exact reviewed source tree. Record outstanding structural findings rather than converting technical test passes into general architecture approval.

The user authorized publishing the current foundation, then separately selected required-check protection with no reviewer requirement. Review the concrete inventory/diff and available verification before publishing changes through the protected path. These authorizations do not accept ADRs or authorize Phase 2.

### Structural findings for the approval review

Technical test passes do not resolve every literal procedure-layering requirement. The following findings were recorded against the published baseline through 06afd20:

- [High] `cmd/warband/main.odin` `main()` L21 calls `read_command()` directly -> orchestration reaches argument parsing rather than calling only Mid decisions.
- [High] `scripts/check_docs.py` `main()` L13 and L15 calls inventory loading and presentation -> orchestration crosses directly into filesystem/parsing/reporting boundaries.
- [High] `scripts/build_manifest.py` `main()` L18 reads/parses JSON and L28 hashes executable bytes alongside architecture validation -> the entry function mixes technical operations with decisions and exceeds the High size limit.

These are concrete instances of the already recorded effect-dispatch/layering question. A review must choose a compliant boundary arrangement or explicitly approve revised guidance before claiming complete structural compliance. Do not label I/O wrappers pure domain functions or silently accept an exception through ADR-0004. Publication of the current foundation does not resolve these findings or claim structural approval.

On 2026-10-11 the owner selected Option A in [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md): preserve strict High/Mid/Low. The fourth-level entrypoint proposal is not selected and its engineering wording is removed. The [focused review](../engineering/phase1-effect-composition-review.md) maps the actual three entrypoint graphs and records the transitive-purity contradiction. No legal complete composition is established; application-code correction stops there. [Candidate evidence](../verification/phase1-entrypoint-evidence.md) remains behavioral evidence only. PR #3 stays draft, no finding closes, and runtime authority rules are unchanged.

## Gate 2 Select and connect the hosted repository

Repository selection and remote configuration are complete: `origin` is `https://github.com/progentic/Warband.git`, the repository is public, and its default branch is `main`. Existing authentication is unchanged. Commit/push and required-check protection are separately authorized. Apply subsequent changes through the protected path; do not infer ADR ownership from the GitHub account.

The foundation is integrated with the existing remote history. Publish subsequent reviewed changes through the protected path and run the complete Phase 1 workflow. Preserve the observed contexts in [protection evidence](phase1-protection-proposal.md). Primary Linux compiler/build/test jobs remain on `ubuntu-latest`; retain the Ubuntu 24.04 guard and reject unexpected OS changes. A moving runner label does not freeze dependency inputs.

## Gate 3 Preserve actual CI evidence

The first published workflow wrote a Linux success summary. The subsequent runner-evidence change captures compiler, build, governance, test, and smoke output into platform-specific `out/` logs. Explicit `shell: bash` preserves fail-fast and pipefail behavior when logging through `tee`. A local failure control verified that producer exit 7 remains exit 7 and its log is retained; a successful producer remains successful.

The workflows upload only their `out/` evidence directories after success or failure, using a reviewed full action SHA and `if: always()`. Hidden files, source credentials, `.git`, `.local`, VM state, and provider data are excluded. Unique artifact names contain platform, tested source SHA, and run attempt; the source SHA is also stored in each directory. Missing evidence fails the upload; checkout/setup infrastructure failures may have only native Actions logs. All three success artifacts at d6448e1 were downloaded and inspected, including archive digests, source identities, binary hashes/metadata, reports and logs. The subsequent protection probe also demonstrated failure-time upload in all three jobs; see [protection evidence](phase1-protection-proposal.md).

The public official upload-artifact v4.6.2 commit is `ea165f8d65b6e75b540449e92b4886f43607fa02`. Its action metadata and configured inputs were inspected before adding it. The action remains pinned to that full SHA. Routine artifacts use 30-day retention; acceptance evidence still needs a durable archive and restore verification.

Retain source/workflow SHA, resolved runner image/version, Odin SHA and report, LLVM/C++ versions, exact package receipts, build flags, binary SHA-256 and architecture/linkage, complete test identities/counts, and failed-stage logs. Artifact retention must fit repository policy; propose 30 days for routine run evidence and export acceptance evidence into a durable maintainer-controlled archive. A successful upload is not proof the tests passed. PR artifacts remain untrusted data and must not be executed or deployed by a privileged follow-up job.

## Gate 4 Define dependency retention and recovery

Exact Ubuntu package revisions can disappear from current mirrors. Continue failing closed when the locked revision is unavailable. Do not substitute another LLVM 19 patch, add a new repository silently, disable package signatures/hash checks, or remove the OS guard.

Propose a maintainer-owned dependency archive containing the complete transitive package set, original signed release/index metadata, exact revisions/architectures, upstream URIs, SHA-256 manifests, and the tested Odin source revision. Retain the reviewed Homebrew bottle plus its digest and required native dependency versions. Select archive custody/storage and retention during governance review; no external archive exists yet.

Validate recovery in a clean matching guest with empty caches: verify provenance/signatures and every package digest, install the exact locked toolchain, assert actual versions, rebuild Odin/Warband, and rerun the full gate. Retention is not complete until this restore test succeeds.

Ubuntu's official snapshot service is an alternative recovery source. A concrete snapshot must be reviewed and tested for the exact package revisions and dependency closure before use. Keep signature, hash, and metadata validity checks; an unavailable or unverifiable snapshot blocks the build. An archive/snapshot change needs recorded provenance and approval, not an automatic fallback. Retain old lock inputs until a reviewed replacement has passed both platform gates, plus an owner-approved recovery period.

## Gate 5 Close governance and enforce checks

Assign a responsible ADR-0004 owner and reviewer. Review implementation evidence, the source baseline, hosted results, dependency retention/recovery, and unresolved procedure-layering concerns. Record approval separately from technical results. Change Proposed to Accepted only after explicit governance approval and the associated documentation/traceability review; no owner or acceptance is inferred here.

Configure supported branch protection/rulesets only after the account/repository/plan is known and the actual named jobs have run. Require the observed checks and appropriate review for source, contracts, toolchain, and workflow changes. Inspect the effective settings and prove an unpassing change cannot merge through the intended path. Document unsupported controls instead of claiming enforcement.

Before the user's protection selection, API inspection found `main` unprotected, required checks off, and no repository or inherited rulesets. That inspection changed no settings. The hosted run also identified action-runtime deprecation and an announced ubuntu-latest migration; these maintenance findings and the retained fail-closed guard are recorded in [runner evidence](../verification/phase1-publication-evidence.md).

The [protection configuration and evidence](phase1-protection-proposal.md) records the user-selected settings, exact observed check contexts/app ID, API readback and a deliberately failing non-draft PR whose merge state stayed BLOCKED. The probe was closed without merging and its branch removed. ADR-0004 ownership remains pending user input.

[ADR-0006](../decisions/0006-hosted-linux-runner-compatibility.md) is the Proposed compatibility record, with a review deadline of 2026-10-18. It records options and required evidence; it does not change the current OS guard, toolchain lock or runner label.

## Gate 6 Prepare Phase 2 design

[ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md) is a Proposed design draft. It addresses event encoding, anchors, evidence provenance, transactional acceptance, capability consumption, uncertain execution outcomes, and deterministic replay. Its open decisions and verification matrix must be reviewed before any Phase 2 code is authorized.

No general agent orchestration, provider integration, new execution surface, distributed consensus, or production deployment belongs to this closure plan. Phase 1 acceptance does not itself authorize Phase 2 implementation.

## Current gate status

| Gate | Current disposition |
|---|---|
| Local technical foundation | PASS; previously recorded Linux and macOS evidence |
| Source baseline review and foundation commit | Published as 53415e7; original remote commit preserved; ignored input/state excluded |
| Repository connection | Configured and verified; existing authentication unchanged |
| Hosted runs | All six workflow runs across 53415e7, d6448e1 and 8da731e passed |
| Runner evidence | Success artifacts inspected at d6448e1; all three failure uploads demonstrated and inspected in protection probe |
| Dependency recovery | Durable archive and clean restore test pending |
| Runner migration | ADR-0006 Proposed; owner/option/review pending before 2026-10-19 rollout |
| Required checks | Configured with no reviewer requirement; readback and blocked failing-PR evidence recorded |
| Owner assignment and ADR acceptance | Pending user input/review; ADR-0004 remains Proposed |
| Procedure hierarchy | Option A selected; legal effect composition unresolved; all three findings open; PR #3 draft |
| ADR-0005 design | Proposed draft only |
| Phase 2 implementation | Not authorized |

References: [GitHub shell failure semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), [artifact behavior](https://github.com/actions/upload-artifact/tree/ea165f8d65b6e75b540449e92b4886f43607fa02), and [Ubuntu snapshot service](https://snapshot.ubuntu.com/).
