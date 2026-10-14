#!/usr/bin/env bash
# Build the reviewed source revision; reject compiler/dependency substitution.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test "$(git rev-parse --show-toplevel)" = "$project_root"
: "${LLVM_CONFIG:?Set LLVM_CONFIG to the exact platform-pinned executable}"
: "${CXX:?Set CXX to an explicit compatible clang++ executable}"
platform="${1:?usage: build_odin.sh linux_amd64|darwin_arm64}"
case "$platform:$(uname -s):$(uname -m)" in
  linux_amd64:Linux:x86_64)
    lock_profile="${WARBAND_TOOLCHAIN_PROFILE-linux}"
    case "$lock_profile" in
      linux|linux_ubuntu2604) ;;
      *) printf '%s\n' 'ERROR: unsupported Linux toolchain profile' >&2; exit 1 ;;
    esac
    expected_release="$(python3 -c 'import json,sys; print(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["ubuntu_release"])' "$lock_profile")"
    # shellcheck source=/dev/null
    . /etc/os-release
    test "$ID:$VERSION_ID" = "ubuntu:$expected_release"
    ;;
  darwin_arm64:Darwin:arm64) lock_profile=macos ;;
  *) printf '%s\n' 'ERROR: build platform does not match host architecture' >&2; exit 1 ;;
esac
source_sha="$(python3 -c 'import json; print(json.load(open("toolchain/odin.lock.json"))["commit"])')"
source_url="$(python3 -c 'import json; print(json.load(open("toolchain/odin.lock.json"))["upstream"])')"
llvm_version="$(python3 -c 'import json,sys; print(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["llvm_version"])' "$lock_profile")"
python3 scripts/toolchain_versions.py --platform "$platform" --profile "$lock_profile" --llvm-config "$LLVM_CONFIG" --cxx "$CXX"
source_dir="$project_root/.local/toolchains/odin-$platform"
mkdir -p "$source_dir" "$project_root/out/$platform"
if [[ ! -d "$source_dir/.git" ]]; then
  git init --initial-branch=main "$source_dir"
  git -C "$source_dir" fetch --depth=1 "$source_url" "$source_sha"
  # Foreign vendor binaries are LFS pointers; this CLI does not use them.
  git -C "$source_dir" -c filter.lfs.process= -c filter.lfs.smudge=cat -c filter.lfs.required=false checkout --detach FETCH_HEAD
fi
checked_sha="$(git -C "$source_dir" rev-parse HEAD)"
test "$checked_sha" = "$source_sha"
source_status="$(git -C "$source_dir" -c filter.lfs.process= -c filter.lfs.clean=cat -c filter.lfs.required=false status --porcelain --untracked-files=normal)"
test -z "$source_status"
python3 - "$source_dir" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
lock = json.loads(Path('toolchain/odin.lock.json').read_text())
actual = hashlib.sha256((Path(sys.argv[1]) / 'build_odin.sh').read_bytes()).hexdigest()
if actual != lock['build_script_sha256']:
    raise ValueError('reviewed upstream build script checksum mismatch')
PY
if [[ "$platform" == darwin_arm64 ]]; then
  # Match the local SDK/dependency platform instead of claiming older OS support.
  macos_version="$(sw_vers -productVersion)"
  export CXXFLAGS="${CXXFLAGS:-} -mmacosx-version-min=$macos_version"
fi
printf 'Odin SHA: %s\nLLVM: %s\nCXX: %s\nCXXFLAGS: %s\n' \
  "$source_sha" "$llvm_version" "$CXX" "${CXXFLAGS:-}" > "$project_root/out/$platform/compiler-inputs.txt"
"$CXX" --version >> "$project_root/out/$platform/compiler-inputs.txt"
make --version >> "$project_root/out/$platform/compiler-inputs.txt"
(
  cd "$source_dir"
  make release
)
export PATH="$source_dir:$PATH"
export ODIN_ROOT="$source_dir"
test "$(command -v odin)" = "$source_dir/odin"
odin version | tee "$project_root/out/$platform/odin-version.txt"
odin report > "$project_root/out/$platform/odin-report.txt"
python3 "$project_root/scripts/assert_toolchain.py" "$platform"
