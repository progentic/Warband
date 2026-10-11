# Phase 1 build and verification

Local Phase 1 implementation is authorized by the [execution directive](phase1-agent-execution-directive.md). [ADR-0004](../decisions/0004-reproducible-odin-toolchain-and-ci.md) remains Proposed. Its decision owner and formal review are unassigned; successful local checks do not accept the ADR.

## Declared phase and verification scope

`project.json` contains exactly one integer `phase` field. Only 0 and 1 are supported. Phase 0 rejects root `src/` and `cmd/` entries; Phase 1 permits foundation source while retaining all required-file, contract-heading, guidance/frontmatter, override, link, and constitutional traceability checks. Missing/malformed/unknown/duplicate-key/boolean phases fail closed. Symlinked inputs fail validation.

The governance scanner excludes only `.git`, `.local`, `out`, `build`, and the retained original bootstrap directory. Ignored generated/input trees are outside the active documentation inventory. Source and tests are still scanned. These filesystem checks are developer controls, not protection from a hostile native process.

The CLI supports `version` and `fixture`. Unknown or extra arguments return exit status 2 with a usage message. `fixture` prints stable verification bytes from supplied identifiers/tick. It has no proposal, execution, policy, capability, evaluator, persistence, state-transition, or learning API. The fixture codec only parses shape; `domain.validate_fixture` independently checks identifiers and fixture schema. Decoded values are not trusted facts.

## Pinned toolchain

`toolchain/odin.lock.json` pins official upstream SHA `8b35c86efb78e9ab5223673a07e02fc2a6884191` and exact platform profiles: Linux LLVM/clang 19.1.1, native macOS LLVM/clang 19.1.7. The reviewed upstream `build_odin.sh` supports LLVM 17–22. Its SHA-256 is also checked before execution. `make release` avoids CPU-specific `release-native` flags. Build and test subprocesses put the pinned LLVM bin directory on PATH for Odin's clang linker, and set the matching ODIN_ROOT. The compiler stays beside its matching `base`, `core`, and `vendor` tree; scripts assert source HEAD, version, PATH resolution, and ODIN_ROOT. Unused vendor binaries remain LFS pointers; no LFS assets are needed by this CLI. Per-command LFS filter overrides avoid changing global Git settings.

Linux uses Ubuntu's signed repositories, explicit `clang++-19` and `llvm-config-19`, and GCC 14 C++ headers. The setup records exact package candidates, installs those exact candidates, and records installed revisions. Linux LLVM/clang must report 19.1.1; mismatch fails the job. The LLVM packages are locked at Debian revision `1:19.1.1-1ubuntu1~24.04.2`. Ubuntu 24.04 is checked explicitly; an unreviewed ubuntu-latest OS change fails closed. `apt-get update` treats partial index failures as errors. Repository package revisions and the hosted OS image remain variable inputs captured in evidence. Strict bitwise reproducibility is not claimed.

Local macOS uses the checksum-pinned Homebrew LLVM 19 bottle extracted under `.local/toolchains/`. `scripts/prepare_macos_llvm.py` verifies its digest before extraction, relocates LLVM's zstd dependency to the already installed Homebrew zstd, and applies ad-hoc signatures to changed local binaries. No global package is installed or changed. The source-build manifest records the actual C++ compiler. CI's disposable macOS runner obtains `llvm@19` through Homebrew and still enforces LLVM/clang version checks.

## Linux commands

Run only on Linux x86-64; macOS is not a substitute.

```sh
bash scripts/install_linux_toolchain.sh
export LLVM_CONFIG=/usr/bin/llvm-config-19
export CXX=/usr/bin/clang++-19
export CXXFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/14
bash scripts/build_odin.sh linux_amd64
bash scripts/build_warband.sh linux_amd64
python3 scripts/check_docs.py
python3 -m unittest discover -s tests/governance -v
python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-linux_amd64/odin --output out/linux_amd64/tests
python3 scripts/verify_cli.py out/linux_amd64/warband
```

`file` and `readelf` must identify an ELF x86-64 binary. `out/linux_amd64/build-manifest.json` contains source/version, LLVM/C++ inputs, runner image, flags, executable checksum, architecture, and linkage. Build, test, or identity failures stop the required check.

## Native macOS commands

Obtain the exact Homebrew bottle URL/digest from the lock file and save it as `.local/toolchains/llvm19.tar.gz`. A GHCR download may need an anonymous public pull token; it is not a GitHub account switch or provider credential. Save temporary download metadata only under `.local/` and remove it after use.

```sh
python3 scripts/prepare_macos_llvm.py
export LLVM_CONFIG="$PWD/.local/toolchains/llvm@19/19.1.7/bin/llvm-config"
export CXX="$PWD/.local/toolchains/llvm@19/19.1.7/bin/clang++"
bash scripts/build_odin.sh darwin_arm64
bash scripts/build_warband.sh darwin_arm64
python3 scripts/check_docs.py
python3 -m unittest discover -s tests/governance -v
python3 scripts/run_odin_tests.py --odin .local/toolchains/odin-darwin_arm64/odin --output out/darwin_arm64/tests
python3 scripts/verify_cli.py out/darwin_arm64/warband
```

The macOS artifact must be ARM64 Mach-O. Outputs and compiler trees are separate from Linux artifacts. Host Homebrew libraries never supply Linux linkage.

## Test completeness

`tests/odin-packages.json` lists two real test packages and five named tests. Discovery scans `tests/odin/` and compares exact package paths and test names to the manifest before executing anything. Supported declarations are `@(test)` followed by a named procedure; unsupported forms fail discovery rather than being omitted. Each package receives a fresh output path and uses the pinned compiler's `ODIN_TEST_JSON_REPORT`. The report must match exact names, total, success count, and every success flag. Old reports are removed before execution. Zero tests, missing packages, wrong names/counts, failed tests, and missing reports cannot produce a green gate.

The governance unit tests mutate real document fixtures. The test-inventory controls explicitly remove a required package and check that completeness fails, separately check a deleted source package, and reject zero/wrong-count/failed reports. Odin tests verify portable golden bytes, injected identity/time preservation, type distinction, invalid length, empty identity, and unknown fixture schema. These are foundation tests, not passing Phase 2 invariant/replay suites.

## CI and VM status

`.github/workflows/phase1.yml` keeps the complete Linux compiler/build/governance/test/smoke sequence on `ubuntu-latest`. A separate macOS ARM portability job builds the same source pin. The retained documentation job keeps its `validate` identifier. Actions are pinned to full reviewed SHAs, checkout does not persist credentials, token permissions are read-only, and only normal pull_request/push triggers are used. Stage logs and platform evidence are retained with `if: always()` and 30-day artifact retention. Explicit bash pipefail preserves producer failures through logging pipelines. Artifacts are untrusted build evidence; they are not deployed or executed by a privileged follow-up. Hosted results are recorded in [publication evidence](../verification/phase1-publication-evidence.md); branch enforcement remains unconfigured.

`vm/lima.yaml` remains an unprovisioned ARM64 VZ development profile with no image selected. `vm/x64-review.yaml` is a separate checksum-reviewed Ubuntu 24.04 x64 QEMU verification profile. Source copies use SSH without host mounts; SSH management binds only to loopback, and application forwarding is disabled. Production architecture remains unset. See [VM preparation](../../vm/README.md) and [current review evidence](../verification/phase1-review-evidence.md). Linux runtime sandbox, recovery, and integrity decisions remain deferred.

## Independent fixture specification

The golden bytes are literal and documented in [the fixture specification](../verification/phase1-fixture-specification.md). A separate Python struct reference cross-checks the static sequence without importing the Odin encoder. Governance fixtures now use tracked documents rather than the ignored bootstrap directory, so the controls work in a fresh checkout.
