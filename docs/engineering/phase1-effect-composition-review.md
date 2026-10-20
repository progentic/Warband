# Phase 1 effect-composition review

**E1 implementation published at v0.0.0; formal finding closure remains separate.** The owner accepted E1 for the three Phase 1 programs in [ADR-0007](../decisions/0007-phase1-entrypoint-boundaries.md). The [engineering standard](coding-standard.md#phase-1-e1-effect-composition) is the canonical permitted-call matrix and exact effectful High allowlist.

## Evidence-based original mismatches and corrected paths

At main `06afd20`, CLI `main -> read_command` coupled external argument acquisition with parsing; documentation `main -> read_inventory / validate_inventory / report_findings` crossed the original High restrictions; manifest `main` mixed raw JSON/hash/inspection with decisions. PR #3 baseline `028dba1` improved supplied-value parsing and pure manifest rules but retained effectful command decisions and broad technical acquisition/publication facades.

Under the original unchanged restrictions, High could reach only transitively pure Mid, and Low could not coordinate upward: no executable input/output path was legal. E1 expressly qualifies High calls in the listed scope; it does not claim every original restriction remains unchanged. E2 and a fourth level are not selected.

Current paths:

- CLI: High `main -> Low read_arguments -> Mid parse_command -> Mid describe_command -> Low write_result -> Low exit_with_status`. Arrows here denote execution order; actual callee edges are below. Presentation chooses stream/format/content/status before any output. No Mid reaches I/O.
- Documents: High `main` invokes High acquisition, pure High validation, Mid status selection, Low reporting and Low termination. Acquisition returns string/value observations; pure rules never receive Path handles.
- Manifest: High `main` first invokes Mid platform validation; High artifact acquisition precedes Mid format/machine validation; only then does High build acquisition inspect linkage/provenance. Pure High construction validates all observations before High publication writes evidence.

## Complete project procedure hierarchy

P means no external effects in the full reachable call path; E means direct or transitive external observation/output. Primitive constructors, constants and immutable record declarations are data, not orchestration procedures. APIs/builtins in the calls column are primitive operations at Low or pure record/collection operations in unchanged supplied-value rules. Every project procedure used by these programs is listed; test/toolchain procedures and unused fixture decoding are outside this graph.

### `scripts/check_docs.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High E | `main` | Coordinate the approved program | `describe_validation`, `exit_with_status`, `project_root`, `read_inventory`, `report_findings`, `validate_inventory` | Listed High / pure Mid / reviewed Low |

### `scripts/document_io.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High E | `read_inventory` | Sequence documentation observations | `assemble_inventory`, `child_path`, `collect_paths`, `inspect_catalog`, `read_document_links`, `read_documents`, `read_phase`, `readable_markdown` | Listed High / pure Mid / reviewed Low |
| Low E | `collect_paths` | Materialize enumerated paths | `tuple`, `walk_files` | Low / technical APIs; no upward calls or policy |
| Low E | `inspect_catalog` | Observe path catalog metadata | `FileCatalog`, `frozenset`, `path.is_symlink`, `path.relative_to`, `root.iterdir`, `str`, `tuple` | Low / technical APIs; no upward calls or policy |
| Low E | `readable_markdown` | Observe readable Markdown paths | `path.is_symlink`, `tuple` | Low / technical APIs; no upward calls or policy |
| Low E | `read_documents` | Read supplied document paths | `read_document`, `tuple` | Low / technical APIs; no upward calls or policy |
| Low E | `read_document_links` | Read supplied link sources | `read_links`, `tuple` | Low / technical APIs; no upward calls or policy |
| Low E | `walk_files` | Enumerate repository paths | `directory.iterdir`, `path.is_dir`, `path.is_file`, `path.is_symlink`, `sorted`, `walk_files` | Low / technical APIs; no upward calls or policy |
| Low E | `read_document` | Read document content/metadata | `Document`, `FRONTMATTER_PATTERN.search`, `IDENTIFIER_PATTERN.findall`, `bool`, `frozenset`, `path.read_text`, `path.relative_to`, `path.stat`, `str`, `text.splitlines` | Low / technical APIs; no upward calls or policy |
| Low E | `read_links` | Read/extract link representations | `LINK_PATTERN.findall`, `path.read_text`, `resolve_link`, `target.strip`, `target.strip().startswith`, `tuple` | Low / technical APIs; no upward calls or policy |
| Low E | `resolve_link` | Observe resolved target location/existence | `(path.parent / target.split('#', 1)[0]).resolve`, `Link`, `path.relative_to`, `resolved.exists`, `resolved.is_relative_to`, `root.resolve`, `str`, `target.split` | Low / technical APIs; no upward calls or policy |
| Low E | `read_phase` | Read phase-file representation | `json.loads`, `path.is_file`, `path.is_symlink`, `path.read_text`, `set`, `type`, `unique_object (JSON duplicate-key hook)` | Low / technical APIs; no upward calls or policy |
| Low P | `unique_object` | Reject duplicate JSON keys | `ValueError`, `dict`, `len` | Low / technical APIs; no upward calls or policy |
| Low E | `report_findings` | Present selected result | `format_finding`, `write_line`, `write_optional_line` | Low / technical APIs; no upward calls or policy |
| Low P | `format_finding` | Format supplied finding | `': '.join`, `filter` | Low / technical APIs; no upward calls or policy |
| Low E | `write_optional_line` | Present nonempty selected text | `write_line` | Low / technical APIs; no upward calls or policy |
| Low E | `write_line` | Write selected line | `print` | Low / technical APIs; no upward calls or policy |
| Low P | `child_path` | Join path components |  | Low / technical APIs; no upward calls or policy |
| Low E | `project_root` | Resolve program root | `Path`, `Path(script).resolve` | Low / technical APIs; no upward calls or policy |
| Low E | `exit_with_status` | Apply supplied exit status | `sys.exit` | Low / technical APIs; no upward calls or policy |

### `scripts/governance.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High P | `validate_inventory` | Combine governance rule findings | `contract_findings`, `guidance_findings`, `link_findings`, `phase_findings`, `phase_two_record_findings`, `required_findings`, `symlink_findings`, `traceability_findings` | Pure Mid only |
| Mid P | `assemble_inventory` | Construct supplied-value inventory | `Inventory` | Pure Low only |
| Mid P | `describe_validation` | Select findings/message/status | `DocumentationResult` | Pure Low only |
| Mid P | `required_findings` | Require declared files | `Finding`, `tuple` | Pure Low only |
| Mid P | `phase_findings` | Enforce declared phase | `Finding`, `matches_typed_member`, `tuple` | Pure Low only |
| Mid P | `phase_two_record_findings` | Require Phase 2 records and unambiguous Accepted status | `Finding`, `prefixed_lines`, `tuple` | Pure Low only |
| Mid P | `guidance_findings` | Check guidance constraints | `Finding`, `any`, `sum`, `tuple` | Pure Low only |
| Mid P | `contract_findings` | Require contract sections | `Finding`, `starts_with`, `tuple` | Pure Low only |
| Mid P | `link_findings` | Reject escaped/missing links | `Finding`, `tuple` | Pure Low only |
| Mid P | `traceability_findings` | Compare invariant identifiers | `Finding`, `sorted`, `tuple` | Pure Low only |
| Mid P | `symlink_findings` | Reject observed symlinks | `Finding`, `tuple` | Pure Low only |
| Low P | `matches_typed_member` | Check exact typed membership | `type` | Low / technical APIs; no upward calls or policy |
| Low P | `prefixed_lines` | Extract supplied lines with a literal prefix | `str.startswith`, `tuple` | Pure primitives only |
| Low P | `starts_with` | Compare string prefix | `text.startswith` | Low / technical APIs; no upward calls or policy |

### `scripts/build_manifest.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High E | `main` | Coordinate the approved program | `acquire_artifact`, `acquire_build_observation`, `construct_manifest`, `inspection_paths`, `project_root`, `publish_verified_manifest`, `read_platform_argument`, `validate_architecture`, `validate_machine`, `validate_platform` | Listed High / pure Mid / reviewed Low |
| High E | `acquire_artifact` | Sequence executable identity/header observations | `assemble_artifact`, `executable_identity`, `inspect_elf_header` | Listed High / pure Mid / reviewed Low |
| High E | `acquire_build_observation` | Sequence linkage and remaining build observations | `acquire_compiler_provenance`, `assemble_build_observation`, `hash_bytes`, `inspect_linkage`, `inspect_runner`, `read_bytes` | Listed High / pure Mid / reviewed Low |
| High E | `acquire_compiler_provenance` | Sequence locked compiler/version observations | `capture_odin_version`, `capture_version`, `describe_compiler`, `parse_json`, `read_environment`, `read_text` | Listed High / pure Mid / reviewed Low |
| High E | `publish_verified_manifest` | Publish an already validated record | `manifest_record`, `serialize_json`, `verified_message`, `write_line`, `write_text` | Listed High / pure Mid / reviewed Low |

### `scripts/manifest_rules.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High P | `construct_manifest` | Combine manifest validation and description | `choose_runner_identity`, `describe_manifest`, `validate_architecture`, `validate_machine`, `validate_platform`, `validate_runner_image`, `validate_runner_version` | Pure Mid only |
| Mid P | `assemble_artifact` | Construct supplied identity record | `ArtifactObservation` | Pure Low only |
| Mid P | `describe_compiler` | Describe supplied provenance | `CompilerObservation` | Pure Low only |
| Mid P | `assemble_build_observation` | Construct supplied build observation | `BuildObservation` | Pure Low only |
| Mid P | `validate_platform` | Require supported platform | `ManifestRejected` | Pure Low only |
| Mid P | `validate_architecture` | Require executable format/architecture | `ManifestRejected`, `includes_markers` | Pure Low only |
| Mid P | `validate_machine` | Require Linux machine identity | `ManifestRejected`, `contains_text` | Pure Low only |
| Mid P | `validate_runner_image` | Require hosted image identity | `ManifestRejected` | Pure Low only |
| Mid P | `validate_runner_version` | Require hosted image version | `ManifestRejected` | Pure Low only |
| Mid P | `choose_runner_identity` | Select hosted/local identity |  | Pure Low only |
| Mid P | `describe_manifest` | Describe validated evidence fields | `BuildManifest`, `target_flags` | Pure Low only |
| Low P | `includes_markers` | Compare literal markers | `all` | Low / technical APIs; no upward calls or policy |
| Low P | `contains_text` | Compare literal substring |  | Low / technical APIs; no upward calls or policy |
| Low P | `target_flags` | Encode fixed target flags |  | Low / technical APIs; no upward calls or policy |

### `scripts/manifest_io.py`

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| Low P | `inspection_paths` | Construct technical inspection paths | `InspectionPaths` | Low / technical APIs; no upward calls or policy |
| Low E | `executable_identity` | Capture fixed file inspection | `capture`, `str` | Low / technical APIs; no upward calls or policy |
| Low E | `inspect_elf_header` | Capture applicable header inspection | `capture`, `str` | Low / technical APIs; no upward calls or policy |
| Low E | `inspect_linkage` | Capture fixed platform linkage inspection | `capture`, `command.append`, `str` | Low / technical APIs; no upward calls or policy |
| Low E | `inspect_runner` | Observe runner environment | `RunnerObservation`, `os.environ.get` | Low / technical APIs; no upward calls or policy |
| Low E | `capture_version` | Capture fixed version protocol | `capture`, `str` | Low / technical APIs; no upward calls or policy |
| Low E | `capture_odin_version` | Capture fixed Odin version protocol | `capture`, `str` | Low / technical APIs; no upward calls or policy |
| Low P | `parse_json` | Decode JSON | `json.loads` | Low / technical APIs; no upward calls or policy |
| Low E | `read_text` | Read file text | `path.read_text` | Low / technical APIs; no upward calls or policy |
| Low E | `read_bytes` | Read file bytes | `path.read_bytes` | Low / technical APIs; no upward calls or policy |
| Low P | `hash_bytes` | Hash supplied bytes | `hashlib.sha256`, `hashlib.sha256(data).hexdigest` | Low / technical APIs; no upward calls or policy |
| Low P | `serialize_json` | Serialize supplied record | `json.dumps` | Low / technical APIs; no upward calls or policy |
| Low P | `manifest_record` | Convert record to plain data | `asdict` | Low / technical APIs; no upward calls or policy |
| Low E | `capture` | Capture supplied fixed inspection command | `subprocess.check_output`, `subprocess.check_output(command, text=True).strip` | Low / technical APIs; no upward calls or policy |
| Low E | `write_text` | Write selected evidence text | `path.write_text` | Low / technical APIs; no upward calls or policy |
| Low E | `write_line` | Write selected line | `print` | Low / technical APIs; no upward calls or policy |
| Low P | `verified_message` | Format verified identity |  | Low / technical APIs; no upward calls or policy |
| Low E | `read_environment` | Read named environment value |  | Low / technical APIs; no upward calls or policy |
| Low E | `read_platform_argument` | Read platform argument |  | Low / technical APIs; no upward calls or policy |

### Odin CLI and reachable fixture helpers

| Layer / effects | Function name | Responsibility | Calls | Allowed to call |
|---|---|---|---|---|
| High E | `main` | Coordinate selected command | `read_arguments`, `parse_command`, `describe_command`, `write_result`, `exit_with_status` | Pure Mid / reviewed Low |
| Mid P | `parse_command` | Interpret supplied command token | `read_fixed_argument` | Pure Low only |
| Mid P | `describe_command` | Select presentation/content/status | `fixture.encode`; value constructors | Pure Low only |
| Low E | `write_result` | Render preselected output representation | `output_stream`, `write_bytes`, `write_line` | Low only; no command selection |
| Low E | `output_stream` | Acquire selected stream handle | `os.stdout`, `os.stderr` | Technical API only |
| Low E | `read_arguments` | Observe process arguments | `os.args` | Technical API only |
| Low P | `read_fixed_argument` | Read token from supplied fixed shape | `len`, indexing | Pure primitives only |
| Low E | `write_line` | Write supplied text | `fmt.fprintln` | Technical API only |
| Low E | `write_bytes` | Write supplied encoded bytes | `fmt.fprintf` | Technical API only |
| Low E | `exit_with_status` | Apply supplied exit status | `os.exit` | Technical API only |
| Low P | `fixture.encode` | Encode fixed byte representation | `write_word`; primitive casts/slices | Pure Low helpers only |
| Low P | `fixture.write_word` | Encode one little-endian word | `endian.put_u64`, `assert` | Pure primitives only |

## Structural review and limitations

No forbidden project call edge remains in the listed graph under E1. Pure High `validate_inventory` and `construct_manifest` have only pure Mid descendants; every Mid has only pure Low descendants. Effects stay in the named High acquisition/publication order and Low operations. Low branches select technical representations/protocols from supplied values, not command behavior, architecture acceptance, runner fallback or documentation status. Existing phase JSON shape/duplicate-key parsing is Low representation validation; the accepted phase decision remains Mid `phase_findings`.

Python executable bootstrap only calls High `main`; argument/root acquisition and exit are not performed at module initialization. The existing standard-library JSON duplicate-key hook is a fixed Low-to-Low parser mechanism, not a new callback composition system. No generic dispatch, plugin, lifecycle hook or fourth layer was added. Odin presentation receives enum values, never an executable callback or technical handle in Mid.

Compiler version-query arguments are fixed; LLVM and C++ executable paths are supplied through `LLVM_CONFIG` and `CXX` by the controlled build environment. The [build documentation](phase1-build-and-verification.md#pinned-toolchain) describes the existing version/provenance controls. Publication's validation-before-write ordering does not establish atomic or crash-safe replacement; see [manifest publication limits](phase1-build-and-verification.md#manifest-publication-limits).

One focused structural control rejects effectful pure-module dependencies, Mid-to-Mid calls, raw High APIs and Low upward policy calls, including injected violations. It is deliberately bounded to these Python sources and known dependencies, not a complete language analyzer or runtime security mechanism. The Odin and technical-policy distinction require source review. These findings are eligible for owner evaluation; passing tests alone neither close them nor accept an ADR.

Actual command/platform results are in [candidate evidence](../verification/phase1-entrypoint-evidence.md). Existing constitutional/accepted ADR rules, pins, runners, manifest schema and runtime boundaries are unchanged. ADR-0004 ownership, dependency recovery, ADR-0006 compatibility and Phase 1 acceptance remain independent gates.
