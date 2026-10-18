# ADR-0006: Hosted Linux runner compatibility

- **Status:** Proposed
- **Date:** 2026-10-10
- **Decision owner:** Proto, repository owner (recorded 2026-10-18)
- **Recorded owner direction:** 2026-10-13: Option A, native Ubuntu 26.04 compatibility evaluation only
- **Publication direction:** 2026-10-18: close out and publish the compatibility evaluation; promotion and formal ADR acceptance remain separate
- **Verified baseline:** v0.0.1 (`3675dca25fd68c867cfb4ed5d9bbcddd545d57aa`); publication baseline v0.0.2 (`e83029c77f08b01028ae3a2240a54780435bcab6`)
- **Review deadline:** 2026-10-18, before the announced rollout begins
- **Scope:** Phase 1 build environment; no production architecture or Phase 2 authorization
- **Supersedes:** None
- **Related:** ADR-0004, still Proposed

## Problem

The passing Linux job currently runs on Ubuntu 24.04 through `ubuntu-latest`. GitHub's [runner announcement](https://github.com/actions/runner-images/issues/14748), checked on 2026-10-10, schedules a rolling transition to Ubuntu 26.04 from October 19 through November 19. Different jobs may receive different host images during that period.

The required Linux job retains the Ubuntu 24.04-only profile and LLVM/clang 19.1.1 at exact signed Ubuntu package revisions. The rejection is intentional. A runner upgrade is not evidence that a replacement toolchain is compatible. The existing job should fail rather than install a guessed version.

## Constraints retained

- Keep primary compiler, application build, tests and smoke jobs on `ubuntu-latest`, never `ubuntu-slim`.
- Preserve exact version checks, signed package provenance, the reviewed Odin source SHA, explicit test identities and executable architecture checks.
- Preserve independent hosted evidence. Do not copy native macOS binaries or local success claims into Linux proof.
- Do not select production architecture, alter accepted runtime contracts or add Phase 2 code.
- Do not silently fall back to another image, package source, LLVM patch or cache after a failed check.

## Options for review

| Option | Benefit | Required evidence and limits |
|---|---|---|
| Option A: native Ubuntu 26.04 dependency profile | Keeps the build directly on the moving hosted VM | Inspect real package revisions and Odin compatibility; review an explicit new lock profile; complete clean source builds, architecture, all tests and negative controls before promotion. Owner-selected Option A for evaluation; promotion still requires successful native evidence and separate owner approval. |
| Use a reviewed Ubuntu 24.04 build container on `ubuntu-latest` | Separates the tested build userspace from the changing host OS | Review the official image's x64 digest and provenance, dependency closure and Actions compatibility; preserve explicit bash/pipefail and receipts; record host image, container digest and guest OS separately. This proves a container build, not the future VM sandbox. No digest is selected or container configured yet. |
| Temporarily use an explicit Ubuntu 24.04 runner | Retains the current direct VM build | Requires a user-approved exception to the `ubuntu-latest` constraint. It is not selected by this proposal. |
| Keep the current guard and pause hosted builds after migration | Avoids accepting unreviewed inputs | CI may become unavailable. Keep that failure visible; local verification does not replace the hosted gate. |

GitHub [supports job containers](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/run-jobs-in-a-container) on a Linux runner. Such jobs default to `sh`, so the existing explicit bash setting must be retained if that option is chosen. A plain Ubuntu image also needs reviewed bootstrap dependencies; the current installer assumes `sudo`, Git and Python already exist. These differences require an explicit implementation and independent verification, not merely an added `container` line.

## Proposed sequence

1. Proto is the recorded decision owner. The [owner decisions](../engineering/ubuntu2604-promotion-review.md#owner-decision-2026-10-18) acknowledge the CI-only v3 floor, authorize checks A and B in a separate implementation PR, accept intermittent rollout failures with the existing guard, and set promotion after rollout completion in a separate PR.
2. Prepare the selected profile on an isolated review branch. Use a separately named compatibility check while preserving the required baseline checks.
3. Record the actual host/userspace versions, image digest if applicable, exact package receipts, compiler inputs, source SHA, binary identity and test reports. Compare these with the verified baseline and explain differences.
4. Prove malformed/unknown profiles, unsupported OS versions and wrong LLVM patches still fail. Verify clean builds without inherited compiler caches and the independently specified golden bytes.
5. Promote only the reviewed profile after its hosted checks pass. Preserve old inputs and define rollback without an automatic fallback.

A separately named `Phase 1 Ubuntu 26.04 Compatibility` job now evaluates the explicit `linux_ubuntu2604` profile on `ubuntu-26.04`. It does not replace the required `ubuntu-latest` job, change its default `linux` profile or approve promotion. The [candidate evidence](../verification/ubuntu2604-compatibility-evidence.md) records actual inputs and outcomes.

## Acceptance evidence

Before accepting this decision, retain the chosen option, responsible owner, reviewed lock/configuration diff, actual successful hosted run, complete artifact inspection, fail-closed controls and recovery disposition. If the deadline is missed, report the resulting build interruption instead of weakening the guard.

The Node 20 action-runtime warnings are a separate maintenance task. New action versions need reviewed full source SHAs and an actual hosted run; do not change compiler requirements while updating them.

## Current disposition

Proposed only. The compatibility evaluation is published as v0.0.2; the required Ubuntu 24.04 job, original profile and exact compiler checks remain. The Ubuntu 26.04 profile keeps the reviewed Odin SHA and independently observed exact Ubuntu dependencies. Native builds and existing controls passed, while the executable declares x86-64-v3 rather than the Ubuntu 24.04 binary's baseline-only ISA property. Input inspection traces that floor to native glibc startup/runtime packages; selecting GCC 14 headers alone does not remove it.

Proto acknowledges that floor for CI artifacts only, with the off-runner execution rule in D1. Candidate-specific rejecting cases remain unexecuted; D2 authorizes only checks A and B in their own implementation PR, including the OS diagnostic/no-APT conditions. D3 requires a separate promotion PR after rollout completion, with rollback defined and no automatic fallback. D4 accepts intermittent required-job failures during the window; the guard remains unchanged. Manual re-runs retain the same commit/workflow/declared profile, preserve failed-attempt evidence and identify the actual runner image; a green 24.04 attempt does not demonstrate a 26.04 baseline pass. No runner exception, container, host-OS profile selection or protection bypass is authorized.

2026-10-18: Review deadline met. Owner decisions are recorded in [the promotion review](../engineering/ubuntu2604-promotion-review.md#owner-decision-2026-10-18) (PR #6): both rejecting checks authorized; promotion after the rollout completes; intermittent required-job failures accepted during the rollout window with the guard unchanged. ADR acceptance, dependency archive/recovery and ADR-0004 remain open.
