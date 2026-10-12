# Phase 1 effect semantics: owner decision comparison

**Historical comparison; E1 selected and implementation authorized.** The reviewed comparison baseline was draft PR #3 at `79c2fdf265e34141535d2596738929b16ca3fc57`, based on main `06afd20049af0d26a4953d0353da06e623482c8a`. The owner subsequently selected E1. [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md) is now Accepted by the project owner against v0.0.0; the [engineering standard](coding-standard.md#phase-1-e1-effect-composition) and [actual review](phase1-effect-composition-review.md) govern the implemented candidate. E2 is not selected. The proposed names/graphs below are retained as decision history, not permission for an alternative implementation.

Preserving the three named levels is different from preserving every original restriction. E1 qualifies only the listed High dependencies while preserving universal transitive Mid purity.

## Current versus proposed graphs

Notation: `H`, `M`, `L` are the three levels. `!` marks a direct or transitive external effect; unmarked proposed procedures are pure. A node marked `!` is never described as pure. Names marked `new` are proposed responsibilities, not existing implementation. Language startup invokes `main`; all input/output composition belongs in the mapped procedures, not module initialization or lifecycle hooks.

Current significant edges:

| Entrypoint | Current path | Violations |
|---|---|---|
| Odin | `H main! -> L read_arguments!; M parse_command; M run_command! -> output/exit` | H -> L; purported Mid presentation selector is transitively effectful; it also calls another Mid fixture procedure |
| Docs | `H main! -> L read_inventory!; H validate_inventory; L report_findings!` | H -> L and H -> H; no legal effect bridge |
| Manifest | `H main! -> M platform/format/machine checks; L inspect_artifact!; L inspect_build!; H construct_manifest; L publish_manifest!` | H -> L and H -> H; technical facades also require narrow-operation review |

The current pure coordinators are High because they sequence Mid rule procedures. Calling them Mid without permitting same-level Mid composition merely relocates the forbidden edge.

## E1: High owns explicit, bounded effect composition

### Exact rule difference

Qualify **High calls Mid only** for the three named Phase 1 workflows and their explicitly listed subflows: High may also call related High workflow procedures and reviewed Low technical procedures. Calls are static and visible. High contains no raw library calls, formatting, hashing, parsing or inline policy decisions. Mid remains transitively pure and calls Low pure helpers only. Low still cannot call upward or make policy decisions.

The High -> High qualification is explicit, allowing reuse of `validate_inventory` and `construct_manifest` without duplicate rule aggregation or false Mid labels. Related High acquisition/publication subflows may be effectful; they are marked `!` and listed in scope. This is a change to the High call restriction, not an exempt fourth level.

### Complete proposed application paths

| Program | Proposed path |
|---|---|
| Odin | `H main! -> L read_arguments! -> supplied values; M parse_command -> command; M describe_command(new) -> presentation result; L present_cli_result(new)!; L exit_with_status!` |
| Docs | `H main! -> L project_root(new)!; L read_inventory!; H validate_inventory -> findings; M validation_status(new) -> status; L report_findings!; L exit_with_status(new)!` |
| Manifest | `H main! -> L read_platform_argument(new)!; M validate_platform; H acquire_artifact(new)!; M validate_architecture; M validate_machine; H acquire_build_observation(new)!; H construct_manifest; H publish_verified_manifest(new)!` |

The arrows in each row specify execution order, not a Low procedure calling the next decision procedure. The named High coordinator owns those sequential calls and supplied values. The leaf/composite table below expands the subflows.

Input effects occur only in Low readers/process wrappers. Pure Mid decides command presentation, exit status, platform/architecture acceptance and manifest values. Output effects occur in Low format/write/exit wrappers. No domain decision receives a file handle, subprocess object or callback.

### Minimum changes and costs

- Keep the three entrypoints High. Retain the supplied-value parser, pure High inventory/manifest coordinators, existing rule procedures, frozen records and narrow Low wrappers.
- CLI: separate command-to-presentation decisions from the current effectful `run_command`/`write_fixture`/`reject_command` composition. One closed CLI result record and its fixed presentation routine suffice; no command registry or generic effect interpreter.
- Docs: move status selection out of `report_findings` into a pure Mid decision; reporting only presents already computed findings. Put process exit and any root-path acquisition in explicit Low procedures called by High. Do not add a forwarding validator.
- Manifest: replace broad inspection/publication facades with genuine High subflows calling existing narrow Low primitives and pure Mid observation assembly. Preserve format/machine checks before linkage and all validation before writing. Add procedures only where acquisition or publication is a distinct necessary subflow.
- Documentation: one owner-selected High call qualification, its exact eligible procedure/effect list, ADR-0007 direction update and revised call map. No blanket permission for all High procedures.

**Advantage:** transitive Mid purity and all existing pure rule responsibilities survive; current pure coordinators are reused. **Disadvantage:** the High -> Mid-only rule is explicitly weakened for these flows, requiring a reviewed scope list. Subflow decomposition adds some procedures, but their work is actual acquisition/publication rather than forwarding. **Maintenance:** audit the eligible High call graph when an effect is added. **Verification cost:** behavioral regression gates plus proof that Mid still reaches only pure helpers and that Low has no upward/policy path.

### Authority limit

Eligibility is limited to the three Phase 1 programs and their listed subflows. Permitted effects are process arguments/environment, documentation reads/reporting, and existing build-metadata observation/publication. Existing `capture` use stays tied to the fixed reviewed inspection/version commands and project artifacts. No caller-supplied procedure, arbitrary command registry, model proposal, capability, evaluator or state writer gains access. Runtime authorization procedures are not eligible for this qualification.

## E2: Mid has explicit effectful application procedures and pure decisions

### Exact rule differences

Qualify two Mid restrictions:

1. **Mid is pure** becomes: pure Mid decision procedures remain transitively pure; explicitly listed Mid application-composition procedures may invoke Low effects and are marked effectful.
2. **Mid calls permitted Low helpers only** becomes: Mid may also compose related Mid procedures. Pure Mid may call only pure Mid/Low procedures; effectful Mid may call listed effectful Mid steps, pure Mid decisions and Low technical procedures.

High still calls Mid only. Low still cannot call upward or make policy decisions. `validate_inventory` and `construct_manifest` become pure Mid composite decisions under the expressly changed composition rule, not by claiming their existing Mid calls were previously permitted. This changes Mid's responsibility/purity semantics while retaining three named levels; the effect marker is not a fourth level.

### Complete proposed application paths

| Program | Proposed path |
|---|---|
| Odin | `H main! -> M run_cli(new)! -> L read_arguments!; M parse_command; M describe_command(new); L present_cli_result(new)!; L exit_with_status!` |
| Docs | `H main! -> M run_documentation_check(new)! -> L project_root(new)!; L read_inventory!; M validate_inventory; M validation_status(new); L report_findings!; L exit_with_status(new)!` |
| Manifest | `H main! -> M run_manifest_check(new)! -> L read_platform_argument(new)!; M validate_platform; M acquire_artifact(new)!; M validate_architecture; M validate_machine; M acquire_build_observation(new)!; M construct_manifest; M publish_verified_manifest(new)!` |

Each effectful Mid composition body owns the listed ordered calls. It does actual acquisition/decision/presentation work rather than forwarding a call to a High coordinator. High remains transitively effectful and is marked `!`. Pure decisions use supplied values only; they never receive technical handles or call effectful siblings.

### Minimum changes and costs

- Introduce one top-level Mid application-composition procedure per entrypoint, with only genuine acquisition/publication substeps needed to keep procedures small. Each body contains explicit work; it is not a renamed supposedly pure I/O wrapper.
- Reuse the same pure CLI-result/status decisions and narrow technical primitives required by E1. Pure inventory/manifest aggregators retain their logic but gain an owner-authorized Mid-composite classification and permitted Mid -> Mid edges.
- Related acquisition/publication subflows are effectful Mid steps rather than High subflows. No generic dispatcher, injected callbacks or effect-plan interpreter is added.
- Documentation: an explicit effectful Mid scope list, permitted-call matrix and transitive-purity rule for pure Mid. Every direct/transitive effect must be marked in review.

**Advantage:** High -> Mid-only survives; effect composition is visible in concrete application procedures. **Disadvantage:** Mid no longer uniformly means pure decisions; reviewers must distinguish pure and effectful procedures, and two pure coordinators change classification under an explicitly amended rule. **Maintenance:** effect propagation and pure/effectful Mid dependencies require continuing review. **Verification cost:** the same behavioral gates plus checks that pure Mid never reaches effectful Mid/Low and that only the listed application compositions perform effects.

### Authority limit

Only the three listed Phase 1 compositions/substeps may be effectful Mid. Domain decisions, authorization, independent runtime evidence evaluation and authoritative transitions remain pure and are not admitted to that scope. An effectful Mid procedure cannot authorize itself, pass a technical handle into a decision, or select arbitrary procedures/commands from untrusted data. No new runtime surface is introduced.

## Exact permitted-call matrices

`P` means transitively pure; `E` means effectful, directly or transitively. Eligibility lists are scoped to these programs and are part of the owner decision, not inferred from a procedure name.

| Caller | E1 permitted callees | E2 permitted callees | Still forbidden |
|---|---|---|---|
| Eligible High composition | Related listed High P/E, Mid P, reviewed Low P/E | Mid P/E only | Raw library operations/inline policy in High; unlisted effects |
| Other High | Mid P only | Mid P only unless separately authorized | Applying this Phase 1 qualification to runtime authority |
| Pure Mid | Low P only | Mid P and Low P | Any direct/transitive effect; technical handles in decisions |
| Effectful Mid | Not permitted | Listed related Mid P/E and Low P/E | High calls; unlisted compositions; false purity claims |
| Low | Low technical helpers/external technical APIs; no upward calls | Same | High/Mid calls; policy decisions; arbitrary domain dispatch |

Neither option permits callbacks, reflection, module/lifecycle composition or renamed forwarding to bypass a forbidden edge. Existing Low facades must be decomposed where they combine distinct operations or decisions; neither option approves them merely because they were previously labelled technical.

## Expanded procedure hierarchy and effects

These groups cover project procedures in the proposed paths. Language/standard-library primitives are reached only through the listed Low operations. An asterisk in a call means external effects; the callee tables above determine caller eligibility.

| Layer E1 / E2 | Function or group | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| H E / H E | Three `main` procedures | Own program flow / invoke its application composition | E1 paths / E2 `run_*` | Exact matrix above |
| Absent / M E | `run_cli`, `run_documentation_check`, `run_manifest_check` (new) | Perform concrete application composition | Listed Mid steps, pure decisions and Low effects | E2 M P/E and L P/E only |
| H E / M E | `acquire_artifact`, `acquire_build_observation` (new) | Sequence narrow input observations and assemble supplied data | Existing Low readers/process/hash/parse primitives; pure Mid assembly | E1 eligible H/M/L; E2 M/L; no raw library calls |
| H E / M E | `publish_verified_manifest` (new) | Serialize and publish an already validated record | `manifest_record`, `serialize_json`, `write_text*`, `write_line*` | E1 reviewed Low; E2 Low |
| H P / M P | `validate_inventory` | Combine existing governance findings | Seven rule procedures below | E1 Mid only; E2 pure Mid |
| M P / M P | `required_findings`, `phase_findings`, `guidance_findings`, `contract_findings`, `link_findings`, `traceability_findings`, `symlink_findings` | Apply existing supplied-inventory rules | Existing pure primitives including `matches_typed_member`, `starts_with` | Low P only |
| H P / M P | `construct_manifest` | Validate supplied observations and construct existing schema | Seven manifest decisions below | E1 Mid only; E2 pure Mid |
| M P / M P | `validate_platform`, `validate_architecture`, `validate_machine`, `validate_runner_image`, `validate_runner_version`, `choose_runner_identity`, `describe_manifest` | Preserve manifest decisions and values | `includes_markers`, `contains_text`, `target_flags` | Low P only |
| M P / M P | `parse_command`, `describe_command` (new) | Interpret supplied arguments / select the allowed presentation result | Pure count/token primitives and fixture encoding | Low P only; no I/O |
| M P / M P | `validation_status`, observation assembly (new as needed) | Select existing exit status / construct typed supplied observations | Pure primitives | Low P only |
| L E / L E | `read_arguments`, project/platform input readers (new as needed) | Acquire explicit external inputs | `os.args` / `sys.argv` / root/environment reads | Technical APIs; no policy calls |
| L E / L E | `read_inventory`, `walk_files`, `read_document`, `read_links`, `read_phase`, `resolve_link` | Acquire/parse documentation observations | Filesystem operations, existing parse primitives | Technical operations only; narrow facade review required |
| L P / L P | `unique_object`, `matches_typed_member`, `starts_with`, manifest text/flag helpers | Existing parsing/data primitives | Technical primitives | No upward calls |
| L E / L E | `capture`, `read_text`, `read_bytes`, `inspect_elf_header`, `inspect_linkage`, `inspect_runner`, narrow input/version readers | Acquire fixed build observations | Fixed subprocess commands and filesystem/environment reads | Technical APIs; no validation/authorization decisions; split any multi-operation facade that fails narrow-operation review |
| L P / L P | `parse_json`, `hash_bytes`, `manifest_record`, `serialize_json`, path/command preparation as needed | Parse/hash/convert supplied technical data | Existing primitives | No upward calls or policy |
| L P / L P | `fixture.encode`, `write_word` | Encode the existing fixed fixture | Endian primitives on a local result buffer | No external effect or policy |
| L E / L E | `present_cli_result` (new), `write_line`, `write_bytes`, `write_error`, reporting, `write_text`, `exit_with_status` | Present preselected data / apply preselected status | Stdout/stderr/files/process exit | Technical APIs; no command permission or success decision |

The CLI result is a fixed presentation record for the existing two commands and rejection output, not a generic action/command registry. Status selection and fixture construction leave the effectful presentation helpers. The current `run_command`, `write_fixture`, `reject_command`, broad `inspect_build` and `publish_manifest` sequences are replaced/decomposed where their mixed responsibilities require it; they are not retained through a new name alone.

There is no remaining forbidden edge in either proposed graph **if and only if** its exact qualifications are selected and the outlined genuine responsibility splits are implemented. Against the current unqualified rules, both graphs remain forbidden and neither is authorized.

## Reviewable diff and regression plan

| Affected source | Expected changes after selection only |
|---|---|
| `cmd/warband/main.odin` | Keep supplied-value parsing; separate pure presentation decisions from output; preserve fixed bytes, streams and exit codes. E1 owns effects in High; E2 adds its concrete Mid composition. |
| `scripts/check_docs.py`, `scripts/document_io.py`, `scripts/governance.py` | Reuse every inventory/rule check; separate pure status decision from reporting; put input/exit acquisition explicitly in Low. No forwarding validator. E2 requires the explicit pure-composite Mid classification. |
| `scripts/build_manifest.py`, `scripts/manifest_io.py`, `scripts/manifest_rules.py` | Reuse frozen observations/pure rules/narrow primitives; split broad acquisition/publication into the selected coordinating level; preserve platform/format/machine checks before linkage, full validation before publication, schema and serialized byte parity. |

Smallest documentary change after selection: append the owner's exact E1 or E2 qualification to ADR-0007, update only the relevant engineering call rule/purity wording and scope list, then replace the proposed map with the actual reviewed graph. ADR status/owner and Phase 1 acceptance remain separate. No accepted ADR, compiler/dependency pin, runner/OS requirement, production architecture or runtime contract changes.

Structural proof requires a complete static call/effect review of these paths: every procedure has one of three levels; every direct/transitive effect is marked; permitted edges match the selected matrix; pure decisions have no effectful descendants; Low has no upward/policy path; no dynamic dispatch or bootstrap escape exists. Source/import checks alone do not prove purity, and a passing build does not prove structure. No test is added solely to mirror names or count wrappers.

Behavioral regression requires existing phase-aware governance; all 21 Python controls; both Odin packages/five named tests; CLI smoke and independent 25-byte golden fixture; real old/new manifest parity against 79c2fdf using the same binary/environment; rejected operations preserving the prior manifest; Linux x64 and macOS ARM64 architecture checks; applicable actionlint/shellcheck/diff review; and complete hosted jobs at the resulting PR head. Add a test only if the selected implementation changes behavior not already covered. Preserve old evidence, and do not attribute baseline results to an untested implementation.

## Rejected non-solutions and owner gate

Mechanical Mid I/O forwarding remains impure under the old rule. A Low callback to a decision procedure calls upward. A pure effect-description alone leaves execution unclassified. A module/global/lifecycle escape hides composition. These are not technically viable alternatives under the unchanged rules and are not offered as a third choice.

The owner selected and authorized E1's bounded High call qualification. The alternatives above preserve the three named levels but change different original restrictions; they are decision history, not permission to implement E2. Formal ADR acceptance, finding closure, merge and Phase 2 authorization remain separate.
