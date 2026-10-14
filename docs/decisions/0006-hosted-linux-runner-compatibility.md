# ADR-0006: Hosted Linux runner compatibility

- **Status:** Proposed
- **Date:** 2026-10-10
- **Decision owner:** Unassigned for formal acceptance
- **Recorded owner direction:** 2026-10-13: Option A, native Ubuntu 26.04 compatibility evaluation only
- **Verified baseline:** v0.0.1, commit `3675dca25fd68c867cfb4ed5d9bbcddd545d57aa`
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

1. The owner selected Option A for evaluation. Assign formal ownership and review the resulting evidence before promotion; keep the primary Ubuntu 24.04 guard until separate owner approval.
2. Prepare the selected profile on an isolated review branch. Use a separately named compatibility check while preserving the required baseline checks.
3. Record the actual host/userspace versions, image digest if applicable, exact package receipts, compiler inputs, source SHA, binary identity and test reports. Compare these with the verified baseline and explain differences.
4. Prove malformed/unknown profiles, unsupported OS versions and wrong LLVM patches still fail. Verify clean builds without inherited compiler caches and the independently specified golden bytes.
5. Promote only the reviewed profile after its hosted checks pass. Preserve old inputs and define rollback without an automatic fallback.

A separately named `Phase 1 Ubuntu 26.04 Compatibility` job now evaluates the explicit `linux_ubuntu2604` profile on `ubuntu-26.04`. It does not replace the required `ubuntu-latest` job, change its default `linux` profile or approve promotion. The [candidate evidence](../verification/ubuntu2604-compatibility-evidence.md) records actual inputs and outcomes.

## Acceptance evidence

Before accepting this decision, retain the chosen option, responsible owner, reviewed lock/configuration diff, actual successful hosted run, complete artifact inspection, fail-closed controls and recovery disposition. If the deadline is missed, report the resulting build interruption instead of weakening the guard.

The Node 20 action-runtime warnings are a separate maintenance task. New action versions need reviewed full source SHAs and an actual hosted run; do not change compiler requirements while updating them.

## Current disposition

Proposed only. Option A evaluation is authorized on the separate review branch; acceptance and promotion are not. The required Ubuntu 24.04 job, original profile and exact compiler checks remain. The Ubuntu 26.04 profile uses the same reviewed Odin SHA and an independently observed exact Ubuntu dependency set. Its native build and existing controls passed at 7402fae, but the produced artifact declares x86-64-v3 rather than the baseline-only ISA property of the Ubuntu 24.04 binary. That CPU-floor difference must remain explicit in owner promotion review; no generic-x64 deployment claim is established. No fallback or container is introduced. Dependency archive/recovery, formal ownership and ADR-0004 acceptance remain open.
