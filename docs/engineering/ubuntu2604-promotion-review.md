# Next task: Ubuntu 26.04 promotion decision and focused rejection evidence

- **Status:** Owner decisions recorded; checks A and B authorized for a separate implementation PR; no tests, promotion, fallback or ADR acceptance implemented
- **Date:** 2026-10-18
- **Publication baseline:** v0.0.2 / `e83029c77f08b01028ae3a2240a54780435bcab6`, merged through [PR #5](https://github.com/progentic/Warband/pull/5)
- **Related:** [ADR-0006](../decisions/0006-hosted-linux-runner-compatibility.md), [compatibility evidence](../verification/ubuntu2604-compatibility-evidence.md), [test necessity standard](coding-standard.md#test-necessity)

## Required decisions

1. **x86-64-v3 floor.** Acknowledge the x86-64-v3 floor of the selected native glibc CRT/runtime for CI artifacts only. This selects no production architecture and establishes no older-CPU deployment compatibility.
2. **Focused rejecting checks.** Decide whether to authorize checks A and B below before promotion, or retain the documented unexecuted-case qualification. Existing positive builds and 22 controls do not supply native-profile rejection evidence.
3. **Rollout window (Oct 19 – Nov 19).** GitHub's [announcement](https://github.com/actions/runner-images/issues/14748), rechecked 2026-10-18, schedules a rolling `ubuntu-latest` migration, and ADR-0006 records that different jobs may receive different host images. The required job keeps the 24.04-only profile and fails closed, so runs that land on 26.04 will fail. Options: accept intermittent failures; approve an explicit 24.04 runner exception; use a reviewed 24.04 build container; or select the profile by detected host OS.
4. **Cutover timing.** Promote the 26.04 profile after the rollout completes, as a separate change with rollback defined and no automatic fallback. The primary job retains `ubuntu-latest` and all required check names and protections.

## Recommendation

Authorize both checks; acknowledge the floor with the off-runner rule; accept intermittent failures during the window; promote after the rollout completes.

## Owner decision (2026-10-18)

Decided by: Proto, repository owner, acting as decision owner for ADR-0006.

- **D1, CPU floor: acknowledged.** The x86-64-v3 floor applies to CI artifacts only. No production architecture or older-CPU claim is made. **Rule:** CI artifacts are never downloaded and executed outside the CI runner.
- **D2, rejecting checks: both authorized.** Implement only checks A and B, retain existing tests, and report newly executed negative evidence separately. Conditions for B: assert the specific OS-mismatch diagnostic and a nonzero exit; state in the implementation how "no APT ran" is verified; state whether the diagnostic string is a contract.
- **D3, cutover: after the rollout completes.** Promotion is a separate PR with a defined rollback, no automatic fallback, `ubuntu-latest` retained, and existing check names unchanged.
- **D4, rollout window: accept intermittent failures.** The 24.04 guard is unchanged. No runner exception, container, profile selection by host OS, fallback or protection bypass is authorized. Failures from runs that land on 26.04 are expected and reported per ADR-0006, not worked around. Manual re-runs of the same commit, workflow and declared profile are permitted; retain every failed attempt and its actual runner image, and attribute a green 24.04 re-run only to that supported host.
- **D5, housekeeping: all three recorded in this PR.** ADR-0006 names Proto as decision owner, records both the verified v0.0.1 and publication v0.0.2 baselines, and records that the 2026-10-18 review deadline was met.

Native v3 CI-artifact qualification and promotion direction/timing are decided here; test implementation still requires its own PR. No promotion, fallback or test implementation is performed by this decision record, and ADR-0006 remains Proposed.

## Proposed check A: explicit candidate profile rejects baseline compiler versions

- Problem: a future regression could read the default Linux lock entry despite an explicitly requested linux_ubuntu2604 profile, accepting the old 19.1.1 toolchain.
- Evidence: scripts/toolchain_versions.py adds explicit profile selection; current test_platform_pins_pass_and_wrong_patch_fails exercises only default platform selection. The successful native candidate supplies matching 19.1.7 tools and does not demonstrate this rejecting case.
- Coverage gap: no existing case passes --profile linux_ubuntu2604 with both supplied tool versions at the old baseline 19.1.1.
- Expected value: demonstrate that an explicit native profile cannot silently validate the baseline toolchain instead. Verify the intended mismatch diagnostic rather than any nonzero command result.
- Cost: extend the existing fake-tool helper with an optional profile argument and add one focused case. Roughly 10-20 Python lines, sub-second local execution, no dependency, fixture file, framework or extra compiler build. Reuse existing version fixtures; do not enumerate redundant patch permutations.

## Proposed check B: installer rejects a selected-profile/host OS mismatch before APT

- Problem: bypassing or misbinding the installer's selected OS guard could start package resolution/installation for the wrong Ubuntu profile.
- Evidence: scripts/install_linux_toolchain.sh compares ID:VERSION_ID against the selected lock entry before apt-get update. The native job always uses the matching linux_ubuntu2604 profile; there is no observed mismatching-host rejection.
- Coverage gap: existing Python controls do not execute this installer entry path with a deliberately mismatched selected profile on the real native host. Nonzero exit alone would be inadequate, because a later package/network error could mask a missing OS guard.
- Expected value: on the real 26.04 runner, request the retained linux / 24.04 profile and demonstrate the specific OS-mismatch diagnostic before any APT operation. Keep evidence distinct from source review.
- Cost: a stable diagnostic in the existing OS guard, plus a short pre-install invocation in the existing compatibility job that requires that diagnostic and nonzero status. Estimate 10-20 shell/YAML lines, no additional job, package install, compiler build, mock OS layer or new script. The separate implementation PR will explain the diagnostic contract and how it verifies that no APT operation ran; no code has been written here.

## Non-goals

No additional version permutations, old-CPU execution matrix, package-manager simulation, generated test chain, new orchestration abstraction, Phase 2 implementation or production architecture decision. No need to accept ADR-0004 or close the three abstraction findings as part of this task.

## Implementation handoff

D2 authorizes only checks A and B in a separate implementation PR. Retain the existing tests, run applicable local/hosted gates and report newly executed negative evidence separately. D3 and D4 set the promotion direction and timing; the actual promotion is a separate post-rollout PR with a defined rollback and no automatic fallback. The primary job retains `ubuntu-latest` and all existing required check names/protections. This documentation PR implements neither checks nor promotion.
