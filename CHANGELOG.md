# Changelog

This file records user-visible and architecture-visible changes to Warband.

## Unreleased

### Added

- Locally authorized Phase 1 CLI and deterministic fixtures.
- Phase-aware governance and explicit Odin test inventory with negative controls.
- Pinned source/LLVM inputs, executable architecture checks, and secure CI definitions.
- Project-scoped Lima recipes, including a provisioned x64 verification guest with a reviewed image digest; production architecture remains unset.
- Proposed ADR-0005 design and a Phase 1 closure plan.

The foundation is technically verified locally on Linux x64 and macOS ARM64. Publication of the reviewed source on the selected repository's `main` is authorized. Hosted CI results remain pending. ADR-0004 remains Proposed with an unassigned owner; formal completion is not claimed.

- Initial documentation-only repository bootstrap.
- Runtime constitution.
- Architecture, engineering, security, and verification baselines.
- Architecture decision record templates and initial decisions.
- Root and documentation-scoped `AGENTS.md` guidance.
- ChatGPT Project setup, instructions, and project-source governance.
- Repo-scoped Warband governance review skill.
- Documentation governance validator and GitHub Actions workflow.

No authoritative execution runtime or production release is included.
