#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test "$(git rev-parse --show-toplevel)" = "$project_root"
platform="${1:?usage: build_warband.sh linux_amd64|darwin_arm64}"
source_dir="$project_root/.local/toolchains/odin-$platform"
llvm_bin="$("$LLVM_CONFIG" --bindir)"
export PATH="$source_dir:$llvm_bin:$PATH"
export ODIN_ROOT="$source_dir"
python3 scripts/assert_toolchain.py "$platform"
mkdir -p "out/$platform"
odin build cmd/warband -vet -warnings-as-errors -target:"$platform" -out:"out/$platform/warband"
python3 scripts/build_manifest.py "$platform"
