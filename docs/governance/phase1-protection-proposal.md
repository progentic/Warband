# Phase 1 main protection configuration and verification

The user selected required checks with no reviewer requirement on 2026-10-10. Protection was applied and read back through GitHub's API. The settings include strict required checks, administrator enforcement, blocked force pushes and blocked deletion. Required PR approvals remain unset.

## Observed checks

The completed check runs at `8da731ef0af3d341908d8c74c62d4ccb741b4c79` have these exact names and GitHub Actions app ID `15368`:

| Workflow | Check context required by the API |
|---|---|
| Documentation Governance | `validate` |
| Phase 1 Foundation | `Phase 1 Linux Foundation` |
| Phase 1 Foundation | `Phase 1 macOS Portability` |

These observed contexts, associated with that app, are configured without guessed workflow-name prefixes. An up-to-date branch is required before merge. Administrators are included in enforcement; force pushes and deletion are blocked. Actor restrictions remain unset.

## Review choice

The user chose all three checks without a mandatory reviewer count. Owner assignment for ADR-0004 remains a separate pending decision; neither a GitHub account nor a successful check establishes decision ownership.

## Observed enforcement evidence

API readback confirmed all three exact contexts with app ID 15368, strict status checks, administrator enforcement, disabled force pushes/deletion, and no required reviewer count.

Disposable [PR #1](https://github.com/progentic/Warband/pull/1) changed only `project.json` from supported phase 1 to unsupported phase 2. It was not a draft and had no merge conflict. The [documentation run](https://github.com/progentic/Warband/actions/runs/38106148961) and both platform jobs in the [foundation run](https://github.com/progentic/Warband/actions/runs/38106148923) failed on `invalid_phase`. After all checks completed with FAILURE, GitHub still reported the PR's merge state as BLOCKED. No merge was attempted or performed.

All three jobs uploaded evidence despite failure. Downloaded governance logs contain `ERROR: invalid_phase: project.json`; the platform artifacts have no Odin test reports because those steps were correctly skipped. These intentionally red probe runs are negative controls, not successful builds or unexpected baseline failures.

The probe was closed without merging and its disposable branch deleted. `main` remained at `8da731e` during the probe. Its invalid phase was never introduced into main. API responses, check/merge state and downloaded evidence are retained locally under `.local/closure-review/`; the linked closed PR and runs preserve the hosted record subject to GitHub retention.

Subsequent changes follow the protected review path. Do not turn off enforcement to continue direct pushes, force-push, or silently use an administrator bypass. This demonstrates the observed blocked merge path and settings; it does not prove future administrators cannot change protection. Branch protection protects source review and CI gates; it does not establish Warband's future runtime authority or sandbox guarantees.
