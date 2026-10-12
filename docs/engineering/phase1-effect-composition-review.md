# Phase 1 effect-composition review

**Verdict: no compliant executable composition has been established under the unchanged rules.** Option A is the owner's direction. This review stops at the incompatibility; it introduces no code, new level, dispatcher, callback scheme or privilege. [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) remains Proposed and all three findings remain open.

## Scope and role interpretation

The scope is only `cmd/warband/main.odin:main`, `scripts/check_docs.py:main`, and `scripts/build_manifest.py:main` on PR #3. Their current bodies coordinate workflows, so this map keeps the baseline High roles rather than silently calling them Low or exempt entrypoints.

High coordinates and calls only Mid. Mid applies rules to supplied values, is pure, and may call only permitted Low helpers. Low performs narrow technical work and cannot call High/Mid or make policy decisions. A Mid procedure calling an effectful Low helper is transitively effectful, even when its own body contains no raw library call. Such a helper is not permitted by strict purity.

The tables classify callees by their responsibility for this review. They do not certify every helper's size or single-operation granularity. Some existing technical facades group multiple observations or output operations; calling those Low does not establish full structural compliance.

## Odin CLI

| Actual edge | Role and effect | Result under unchanged rules |
|---|---|---|
| `main -> read_arguments` | High -> Low; reads process-global `os.args` | Forbidden direct High -> Low edge |
| `main -> parse_command` | High -> Mid; count/token decisions use the supplied argument slice | Permitted role edge; no external read in parsing |
| `main -> run_command` | High -> Mid; selects Version/Fixture/Invalid presentation | The edge alone is permitted, but the callee performs output transitively and is not pure |
| `run_command -> write_line` | Mid -> Low; writes stdout through `fmt.println` | Violates Mid purity |
| `run_command -> write_fixture` | Mid -> Mid; forms fixture data, encodes and presents it | Forbidden Mid -> Mid edge; output also violates purity |
| `write_fixture -> fixture.encode -> write_word` | Mid -> Low pure encoding; endian operations modify only the returned local buffer | No external effect in the encoding chain |
| `write_fixture -> write_bytes` | Mid -> Low; writes stdout through `fmt.printf` | Violates Mid purity |
| `run_command -> reject_command -> write_error / exit_with_status` | Decision procedure -> technical rejection sequence; writes stderr and calls `os.exit(2)` | Transitively effectful; the rejection facade also groups more than one technical operation |

Supplied-value parsing is a useful behavior-preserving separation, but it does not make the complete entrypoint graph legal. Moving the argument read into a Mid forwarding procedure would make that procedure observe external state rather than become pure.

## Documentation validator

| Actual edge | Role and effect | Result under unchanged rules |
|---|---|---|
| `main -> read_inventory` | High -> Low technical acquisition facade | Forbidden direct High -> Low edge |
| `read_inventory -> walk_files / read_document / read_links / read_phase` | Technical helpers enumerate/stat/read paths and parse text/JSON | External filesystem observations; no wrapper name removes those effects |
| `main -> validate_inventory` | High -> High; the validator coordinates seven rule procedures | Forbidden High -> High edge |
| `validate_inventory -> required_findings / phase_findings / guidance_findings / contract_findings / link_findings / traceability_findings / symlink_findings` | High -> Mid; supplied-inventory rules return findings | Pure rule composition; assigning the coordinator Mid instead would move the problem to Mid -> Mid calls |
| `main -> report_findings` | High -> Low presentation facade; writes findings/success text and returns status | Forbidden direct High -> Low edge |
| Module bootstrap -> `sys.exit(main())` | Applies the returned status to the process | Moving composition into module/bootstrap statements would require an expressly governed calling context; it is not an approved escape from the three-level rules |

The earlier three-step implementation is readable, but Option A does not permit its effectful composition. No forwarding layer is added to pretend otherwise.

## Build manifest

| Actual edge | Role and effect | Result under unchanged rules |
|---|---|---|
| `main -> validate_platform / validate_architecture / validate_machine` | High -> Mid; supplied-value membership/format/machine checks | Permitted role edges; pure checks |
| `main -> inspect_artifact` | High -> Low technical facade; `file` and Linux `readelf` subprocess observations | Forbidden direct High -> Low edge |
| `main -> inspect_build` | High -> Low technical facade; lock/binary reads, compiler versions, linkage and environment observations | Forbidden direct High -> Low edge |
| `inspect_build -> inspect_linkage / capture / read_text / parse_json / read_bytes / hash_bytes / inspect_runner` | Low technical work; `ldd` or `otool`, subprocesses, filesystem/environment reads and pure parsing/hashing | Effects remain at acquisition; this grouping is not certified as a single narrow primitive |
| `main -> construct_manifest` | High -> High; coordinates validation, runner identity selection and description | Forbidden High -> High edge |
| `construct_manifest -> validate_platform / validate_architecture / validate_machine / validate_runner_image / validate_runner_version / choose_runner_identity / describe_manifest` | High -> Mid; frozen supplied observations, no I/O | Pure call composition is independently useful; it does not authorize its current entrypoint caller |
| Mid rules -> `includes_markers / contains_text / target_flags` | Mid -> Low pure primitives | Permitted helper edges |
| `main -> publish_manifest` | High -> Low presentation facade | Forbidden direct High -> Low edge |
| `publish_manifest -> manifest_record / serialize_json / write_text / write_line` | Converts the record, writes JSON and prints verified metadata | Output effects; grouped publication is not an approved fourth-level adapter |

Actual execution still checks the requested platform, acquires file/header metadata, validates format/machine, then acquires linkage and remaining observations. It constructs/validates the manifest before writing it. This review changes neither that order nor the fields, byte parity, pins or rejection behavior.

## Contradiction and smallest owner decision

Assume the entrypoint retains its High coordination role and all three rules hold:

1. Its only permitted procedure calls are Mid calls.
2. Every reachable Mid procedure must remain pure, including the Low helpers it invokes. Therefore that path cannot acquire process/filesystem input or write/exit externally.
3. A Low I/O procedure cannot call the Mid/High decisions to coordinate a complete application. Reclassifying all decisions as Low would violate Low's ban on policy decisions and the prohibition on silent reclassification.

The CLI requires argument acquisition and observable stdout/stderr/exit behavior. Documentation validation requires filesystem observations and reporting. Manifest verification requires filesystem/process/environment observations and output. Those required effects contradict the reachable pure-only path. Extra Mid wrappers preserve the same transitive impurity; callbacks introduce forbidden upward calls; a pure effect description still needs a legally classified executor. Unclassified bootstrap/lifecycle composition would require an unapproved exception.

**No legal complete call graph is proposed.** The smallest outstanding owner decision is the precise permitted location and semantics of effect composition within the existing three levels. With transitive Mid purity, High -> Mid only, Low's no-upward/no-policy restrictions, and the current entrypoint roles all unchanged, there is no compliant composition. At least one premise needs explicit clarification or qualification, or this correction must remain suspended. This review selects neither an amendment nor Options B/C.

The subsequent [two-option decision comparison](phase1-effect-semantics-options.md) identifies exact possible qualifications, complete proposed paths, permitted-call matrices, minimum changes and verification. Neither option creates a fourth level, but both change an original restriction. Owner selection is required before application-code changes.

## Disposition and verification

Stop application-code correction at this point. PR #3 stays draft; behavior-tested candidate parts are not promoted or declared compliant. Reuse of the supplied-value parser and pure manifest procedures remains subject to a legal complete graph and review. No generic framework or artificial forwarding layer is introduced.

Rerun the existing governance and complete hosted gates for this documentation revision. Record exact commits/runs, keeping behavioral results distinct from structural compliance. Constitution, accepted ADRs, invariant identifiers, application code, compiler/dependency pins, output/manifest behavior and current negative controls remain unchanged by this review. ADR-0004 ownership, dependency recovery and ADR-0006 compatibility remain separate.
