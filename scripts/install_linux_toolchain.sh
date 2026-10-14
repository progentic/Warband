#!/usr/bin/env bash
# Use signed Ubuntu repositories; no remote installer script or fallback version.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test "$(git rev-parse --show-toplevel)" = "$project_root"
test "$(uname -s):$(uname -m)" = Linux:x86_64
lock_profile="${WARBAND_TOOLCHAIN_PROFILE-linux}"
case "$lock_profile" in
  linux|linux_ubuntu2604) ;;
  *) printf '%s\n' 'ERROR: unsupported Linux toolchain profile' >&2; exit 1 ;;
esac
expected_release="$(python3 -c 'import json,sys; print(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["ubuntu_release"])' "$lock_profile")"
# shellcheck source=/dev/null
. /etc/os-release
test "$ID:$VERSION_ID" = "ubuntu:$expected_release"
mkdir -p out/linux_amd64
sudo apt-get -o APT::Update::Error-Mode=any update
locked_revision="$(python3 -c 'import json,sys; print(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["llvm_package_version"])' "$lock_profile")"
package_list="$(python3 -c 'import json,sys; print(" ".join(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["packages"]))' "$lock_profile")"
read -r -a packages <<< "$package_list"
resolved=()
: > out/linux_amd64/package-inputs.txt
for package in "${packages[@]}"; do
  candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')"
  test -n "$candidate"
  test "$candidate" != '(none)'
  case "$package" in
    clang-19|llvm-19-dev|lld-19) candidate="$locked_revision" ;;
    *) if [[ "$lock_profile" == linux_ubuntu2604 ]]; then
         candidate="$(python3 -c 'import json,sys; print(json.load(open("toolchain/odin.lock.json"))[sys.argv[1]]["package_versions"][sys.argv[2]])' "$lock_profile" "$package")"
       fi ;;
  esac
  resolved+=("$package=$candidate")
  printf '%s=%s\n' "$package" "$candidate" >> out/linux_amd64/package-inputs.txt
done
sudo apt-get --print-uris install --yes --no-install-recommends "${resolved[@]}" | tee out/linux_amd64/package-uris.txt > /dev/null
sudo apt-get install --yes --no-install-recommends "${resolved[@]}"
python3 scripts/toolchain_versions.py --platform linux_amd64 --profile "$lock_profile" --llvm-config /usr/bin/llvm-config-19 --cxx /usr/bin/clang++-19
dpkg-query -W "${packages[@]}" > out/linux_amd64/package-installed.txt
dpkg-query -W > out/linux_amd64/installed-packages.txt
ld --version > out/linux_amd64/linker-version.txt
for requested in "${resolved[@]}"; do
  package="${requested%%=*}"
  expected="${requested#*=}"
  test "$(dpkg-query -W -f='${Version}' "$package")" = "$expected"
done
