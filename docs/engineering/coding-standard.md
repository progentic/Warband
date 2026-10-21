# Coding Standard

## Explicit decisions

Security decisions must use named enums or decision types, not bare booleans.

Prefer:

`permit`, `reject`, `require_approval`

Avoid:

`allowed: bool`

## Typed identifiers

Task, run, proposal, event, fact, evidence, and capability identifiers must use distinct types.

## No hidden mutation

Security-sensitive state changes must not occur inside getters, serializers, log functions, constructors, or cleanup code.

## Explicit errors

Fallible operations must return typed errors with stable codes. Errors shown to users must not expose secrets, capability tokens, raw prompts, or restricted data.

## Controlled time and identity

Code that depends on time, random identifiers, or replay behavior should receive those services explicitly so tests can control them.

## Test necessity

Tests must reduce a specific, demonstrable uncertainty. Before implementing a proposed new test, present the following reasoning for owner review:

1. Problem: the concrete failure or regression.
2. Evidence: the supporting code path, defect, changed behavior or requirement.
3. Coverage gap: why existing tests do not address it.
4. Expected value: the uncertainty the test would eliminate.
5. Cost: additional code, runtime, dependencies and maintenance.

If no meaningful coverage gap exists, add no test. A modified file or a test-count target is not justification. Avoid speculative edge-case expansion, repetitive permutations and tests of generated tests that do not improve confidence in Warband's behavior.

## Boundary rule

Raw model output must not cross the proposal-normalization boundary. Raw tool output must not become evidence until an evaluator processes it.

## Default safety

Unknown enum values, tools, policy rules, schema versions, and effect kinds must fail closed.

## Phase 1 procedure structure

Keep orchestration, pure domain decisions and technical operations separate under High/Mid/Low. The owner-authorized Phase 1 E1 qualification below governs only the listed workflows; there is no fourth classification. Outside that scope, High calls pure Mid only. Mid remains transitively pure everywhere. Low has no upward calls or application policy decisions.

The fixture format is portable verification data, not an accepted event-store format. Ticks and identifiers are explicitly supplied; encoding reads no wall clock or random identity.

[ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) is Accepted by the project owner against v0.0.0 / 8afe351 and records the bounded E1 direction. The [actual call/effect review](phase1-effect-composition-review.md) maps the implementation. Structural review and behavioral verification are separate; passing tests alone close no finding.

### Phase 1 E1 effect composition

| Caller | Permitted calls | Restriction |
|---|---|---|
| Listed eligible High | Related listed High, pure Mid, reviewed Low | Only the listed Phase 1 programs/subflows/effects; no raw library calls, parsing, hashing, formatting or direct filesystem manipulation |
| Other High | Pure Mid only | Original rule unchanged |
| Mid | Pure Low helpers only | No direct or transitive external effects or technical handles in decisions |
| Low | Low helpers and technical APIs | No upward calls, policy decisions or application-behavior selection |

The following is the complete eligible effectful High list. Pure High coordinators `governance.validate_inventory` and `manifest_rules.construct_manifest` remain pure and call Mid only.

| Eligible High procedure | Direct permitted Low dependencies | Related High / pure Mid dependencies | External effects |
|---|---|---|---|
| `cmd/warband/main.odin:main` | `read_arguments`, `write_result`, `exit_with_status` | `parse_command`, `describe_command` | Arguments, stdout/stderr, process exit |
| `scripts/check_docs.py:main` | `project_root`, `report_findings`, `exit_with_status` | `read_inventory`, `validate_inventory`, `describe_validation` | Project-root/inventory observations, reporting, exit |
| `scripts/document_io.py:read_inventory` | `collect_paths`, `inspect_catalog`, `readable_markdown`, `read_documents`, `read_document_links`, `read_phase`, `child_path` | `assemble_inventory` | Project paths, metadata/text/phase and link observations |
| `scripts/build_manifest.py:main` | `read_platform_argument`, `project_root`, `inspection_paths` | `acquire_artifact`, `acquire_build_observation`, `construct_manifest`, `publish_verified_manifest`; platform/format/machine decisions | Arguments, artifact/provenance observations, manifest output |
| `scripts/build_manifest.py:acquire_artifact` | `executable_identity`, `inspect_elf_header` | `assemble_artifact` | Fixed `file`/`readelf` inspections |
| `scripts/build_manifest.py:acquire_build_observation` | `inspect_linkage`, `read_bytes`, `hash_bytes`, `inspect_runner` | `acquire_compiler_provenance`, `assemble_build_observation` | Fixed linkage inspection, binary/environment reads |
| `scripts/build_manifest.py:acquire_compiler_provenance` | `read_text`, `parse_json`, `capture_odin_version`, `capture_version`, `read_environment` | `describe_compiler` | Locked configuration and fixed compiler-version queries |
| `scripts/build_manifest.py:publish_verified_manifest` | `manifest_record`, `serialize_json`, `write_text`, `verified_message`, `write_line` | None | Existing manifest destination and status output |

Low dependencies expand only through the technical helpers in the actual review. `capture` never selects application behavior; its callers supply reviewed inspection/version arguments. Compiler executable paths come from the controlled build environment as described in [the build documentation](phase1-build-and-verification.md#pinned-toolchain). Output helpers use the already selected data representation/stream/status. No callable input, registry, general dispatcher or lifecycle path is permitted. Startup only invokes `main`; root/input acquisition occurs explicitly inside the listed flow.

Runtime coordinator, policy engine, capability gateway, evaluator, state writer, recovery and model adapters are not eligible. Adding an effect/procedure requires a scoped review update; this matrix is not general High-to-Low authority. Layering does not enforce a sandbox or authorize a runtime transition.

## Proposed Phase 2 effect qualification

The [ADR-0005 Phase 2 graph](../decisions/0005-event-integrity-acceptance-and-recovery.md#6-proposed-phase-2-effect-qualification) enumerates a separate candidate permission and names its workflows, dependencies and effects. It has no force until explicit ADR acceptance and Phase 2 entry authorization. It neither modifies ADR-0007 nor makes the Phase 1 list general. After acceptance, only that enumerated Phase 2 High list may compose its named effects; all other High calls pure Mid only. Every Mid remains transitively pure and Low has no upward authority. Layer classification does not authorize an action or enforce OS isolation.
