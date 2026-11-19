#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:?usage: test_writer_open.sh linux_amd64|darwin_arm64}"
export ODIN_ROOT="$PWD/.local/toolchains/odin-$target"
export PATH="$ODIN_ROOT:$("$LLVM_CONFIG" --bindir):$PATH"
python3 scripts/assert_toolchain.py "$target"
source_hash=555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76
archive="$PWD/.local/dependencies/sqlite/$source_hash/$target/libsqlite3.a"
test -f "$archive"
out="$PWD/out/$target/writer-open"
mkdir -p "$out"
fixture="$(mktemp -d "$out/fixture.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
report="$fixture/report.json"
odin test tests/integration/writer_open -vet -warnings-as-errors "-out:$fixture/test" \
    "-collection:warband_sqlite=${archive%/*}" "-define:WARBAND_FIXTURE_DIR=$fixture" \
    -define:ODIN_TEST_FANCY=false -define:ODIN_TEST_RANDOM_SEED=1 "-define:ODIN_TEST_JSON_REPORT=$report"
PYTHONPATH=scripts python3 - "$report" <<'PY'
from pathlib import Path
import json
import sys
from test_inventory import TestPackage, validate_report
names = ("two_connections_report_verified_profiles", "unversioned_database_keeps_original_journal_mode")
validate_report(TestPackage("tests/integration/writer_open", names), json.loads(Path(sys.argv[1]).read_text()))
PY
mv "$report" "$out/report.json"
