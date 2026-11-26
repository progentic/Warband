# TaskCreated codec evidence addendum

Collected 2026-11-15 against published source `eb87e70b32da9a37a3078398b5bd434be394159d`, merged by [PR #29](https://github.com/progentic/Warband/pull/29) at `90aa976268a19897697b65efef6f8a9bb5ecc8f3`. This addendum addresses Meta's evidence review of the November 13 local record.

## Retained bundle and provenance limits

The local handoff archive is `.local/task-created-evidence-2026-11-15.zip`, SHA-256 `d187bf42470908eb1d65df81adc22128f314d9b546c4b10b93033af65da2ee81`. Its 48 files include original logs/baseline, original and fresh JSON reports, published source extracts, command arrays with fresh exit codes, all five vector values and SHA256SUMS. Transfer the archive with this record for independent review. Hashes were collected retrospectively and establish integrity from collection onward.

`collection.json` contains each baseline and published-file hash, incremental line count and the newly observed compiler-binary hash. The baseline is a saved uncommitted working tree, with weaker provenance than the published commit. Original per-attempt source snapshots, binary hashes and a machine-readable exit ledger were not retained. The session transcript reports that only test-loop headers changed between focused attempts; the historical bundle alone cannot independently prove that production source stayed identical.

The published diff changes no toolchain lock and introduces only pinned standard-library imports. The recorded execution contains no dependency-install command. This supports the slice's dependency claim; a machine-wide installation audit was not captured.

Meta subsequently reported independent verification of the archive digest, all 47 SHA256SUMS entries, vector reproduction and a corruption probe that failed with exit 1. Meta also verified pledge-file preservation and report consistency. This is reviewer-supplied evidence; Meta could not execute the Darwin Odin toolchain or rerun governance from this bundle. Reviewer eligibility for exception closure remains separately unconfirmed.

The earlier “74 added lines, local and uncommitted” statement referred to this addendum's initial 72 lines and its two-line ADR-0005 pointer. Those post-publication edits were outside the unchanged archive. The codec slice was already published at the commit above. This clarification is additional documentation.

## Commands, exits and test identities

| Observation | Exit/result | Evidence |
| --- | --- | --- |
| Original focused attempt 1 | 1; compiler syntax failure; no tests ran | `original/focused-attempt1.log`, including failing compiler command |
| Original focused attempt 2 | Reported exit 0; 2 successful tests | `original/focused-attempt2.log`, `original-reports/audit.json` |
| Original adjacent attempt 1 | Reported exit 1 before package execution; relative-path ValueError | `original/adjacent-packages.log` |
| Original corrected adjacent attempt | Reported exit 0; 6 identity and 2 custody tests passed | `original/adjacent-packages-attempt2.log`, matching original JSON reports |
| Fresh focused and adjacent reproduction | Captured exit 0; 10 tests across 3 packages | `focused-and-adjacent.log`, `new-reports/*.json`, `collection.json` |
| Fresh vector reproduction and tool identity commands | Captured exits 0 | `reproduce-vectors.py`, `matched-values.json`, compiler/LLVM logs and `collection.json` |

Odin reports `dev-2026-10:8b35c86`; the newly observed compiler checkout is `8b35c86efb78e9ab5223673a07e02fc2a6884191`, and LLVM reports 19.1.7. These are collection-time observations. Exact original compiler-binary identity cannot be recovered from its path alone.

`task_created_encoding_and_digest_match_golden` checks exact bytes, decoded fields, digest, linked head and a changed payload digest producing a changed event hash. `task_created_decoding_rejects_malformed_and_unsupported` checks unknown schema, truncation, excess bytes, kind/producer/version, magic/payload length, seven zero-ID fields, wrong expected epoch and invalid encode input. See the [published assertions](https://github.com/progentic/Warband/blob/eb87e70b32da9a37a3078398b5bd434be394159d/tests/odin/audit/task_created_test.odin).

An event contains its previous head, not a separately stored expected event digest. Hash comparison against trusted custody belongs to the later integrity path; duplicate/replay rejection belongs to the state boundary. These tests establish canonical construction, hashing and structural validation. Durable audit, authenticity and replay guarantees remain outside this slice.

## Independent vector reproduction

The original Python construction followed ADR-0005's field table before the Odin codec was written, as recorded in the execution transcript. The standalone script in this bundle was reconstructed on 2026-11-15 from that specification recipe; it is not the retained original script. It builds genesis, request digest, payload, header and hash inputs using fixed IDs, struct and hashlib, then checks OpenSSL. It neither imports nor reads the Odin implementation. The expected JSON comparison occurs after construction.

| Matched value | Exact result |
| --- | --- |
| payload_hex | `111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f55555555555555555555555555555555` |
| body_hex | `5742455601000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f55555555555555555555555555555555` |
| event_hex | `5742455601000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f555555555555555555555555555555554108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18` |
| event_digest | `e77c263c6f4a468f9a3c9cfb792825c68f4788bff2136385745a6f63379f8035` |
| head | `00e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f` |

## Scope and pledge preservation

The first scope log counted 264 added lines. The increase to 266 added the paragraph beginning “Broader validation initially failed…” and its separating blank line in ADR-0005. Publication added the authorization heading, paragraph and separating blank lines (four lines), yielding 270 incremental lines across eleven files. The execution transcript records those edits; intermediate source snapshots were not retained. Per-file publication counts and before/after hashes are in `collection.json`. `git diff --check` was used only for whitespace validation. The combined published PR also contains the earlier pledge increment, so its total diff is larger.

| Pledge file | Matching saved-baseline and published SHA-256 |
| --- | --- |
| `src/custody/pledge.odin` | `1a9559f1cff4662b8ff3d155f8c4266820b36427ddbbffc400f4cc2051c39115` |
| `tests/odin/custody/pledge_test.odin` | `d7fdb308ed3b5a96b6d287038550ca8ab48c1e5c84b81cd658af78cc9225c43f` |

## Reproduction from the repository root

Set LLVM_CONFIG to the pinned local LLVM 19.1.7 llvm-config. This recipe validates the complete inventory and runs the focused package plus the corrected adjacent invocation with fresh output paths. The runner supplies vet, warnings-as-errors, seed 1, fancy output off and fresh JSON reports.

```sh
export LLVM_CONFIG="$PWD/.local/toolchains/llvm@19/19.1.7/bin/llvm-config"
python3 - <<'PYCODE'
import sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from run_odin_tests import ROOT, read_manifest, discover_packages, execute_package
from test_inventory import validate_packages
packages = read_manifest(ROOT / 'tests/odin-packages.json')
validate_packages(packages, discover_packages(ROOT / 'tests/odin'))
for package in packages:
    if package.path in ('tests/odin/audit', 'tests/odin/custody', 'tests/odin/event_identity'):
        execute_package(ROOT / '.local/toolchains/odin-darwin_arm64/odin',
                        Path('out/task-created-review'), package)
PYCODE
```

After extracting the archive, run `python3 task-created-evidence/reproduce-vectors.py` from the repository root. Verify all archive members against SHA256SUMS before using the evidence. The [hosted publication run](https://github.com/progentic/Warband/actions/runs/43538098333) separately records platform checks for the published PR head; local reruns establish current macOS functional behavior.

Bundled `original/hosted-publication.json` records successful macOS Portability, Linux Foundation and Ubuntu 26.04 Compatibility jobs at `eb87e70`. This establishes the reported hosted results; independent re-execution and detailed artifact verification require their own evidence.
