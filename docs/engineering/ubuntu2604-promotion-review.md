# Next task: Ubuntu 26.04 promotion decision and focused rejection evidence

- **Status:** Proposal for owner review; no tests, promotion, fallback or ADR acceptance implemented
- **Date:** 2026-10-18
- **Publication baseline:** v0.0.2 / `e83029c77f08b01028ae3a2240a54780435bcab6`, merged through [PR #5](https://github.com/progentic/Warband/pull/5)
- **Related:** [ADR-0006](../decisions/0006-hosted-linux-runner-compatibility.md), [compatibility evidence](../verification/ubuntu2604-compatibility-evidence.md), [test necessity standard](coding-standard.md#test-necessity)

## Required decisions

1. Acknowledge the x86-64-v3 floor of the selected native glibc CRT/runtime for CI artifacts only. This selects no production architecture and establishes no older-CPU deployment compatibility.
2. Decide whether to authorize the two focused checks below before promotion, or retain the documented unexecuted-case qualification. Existing positive builds and 22 controls do not supply that missing native-profile rejection evidence.
3. Approve the cutover timing/transition policy separately. GitHub's [announcement](https://github.com/actions/runner-images/issues/14748), rechecked 2026-10-18, begins the ubuntu-latest migration on October 19 and completes it by November 19. Required Ubuntu 24.04 checks still passed on the publication head. Forcing the 26.04 profile while ubuntu-latest supplies 24.04 would fail the exact OS guard. Keep fail-closed behavior; no mixed-OS dispatcher, fallback, explicit-runner exception or branch-protection bypass is authorized by this proposal.

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
- Cost: a stable diagnostic in the existing OS guard, plus a short pre-install invocation in the existing compatibility job that requires that diagnostic and nonzero status. Estimate 10-20 shell/YAML lines, no additional job, package install, compiler build, mock OS layer or new script. Exact implementation and diagnostic are subject to owner review; no code has been written.

## Non-goals

No additional version permutations, old-CPU execution matrix, package-manager simulation, generated test chain, new orchestration abstraction, Phase 2 implementation or production architecture decision. No need to accept ADR-0004 or close the three abstraction findings as part of this task.

## Acceptance of the next task

If authorized, implement only the approved checks, retain the existing tests, run applicable local/hosted gates and report the newly executed negative evidence separately. A promotion change remains a separate owner decision; the primary job must retain ubuntu-latest and all existing required check names/protections.
