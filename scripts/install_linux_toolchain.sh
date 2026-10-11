#!/usr/bin/env bash
# Use signed Ubuntu repositories; no remote installer script or fallback version.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test "$(git rev-parse --show-toplevel)" = "$project_root"
test "$(uname -s):$(uname -m)" = Linux:x86_64
# shellcheck source=/dev/null
. /etc/os-release
test "$ID:$VERSION_ID" = ubuntu:24.04
mkdir -p out/linux_amd64
sudo apt-get -o APT::Update::Error-Mode=any update
locked_revision="$(python3 -c 'import json; print(json.load(open("toolchain/odin.lock.json"))["linux"]["llvm_package_version"])')"
packages=(clang-19 llvm-19-dev lld-19 libstdc++-14-dev make)
resolved=()
: > out/linux_amd64/package-inputs.txt
for package in "${packages[@]}"; do
  candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')"
  test -n "$candidate"
  test "$candidate" != '(none)'
  case "$package" in
    clang-19|llvm-19-dev|lld-19) candidate="$locked_revision" ;;
  esac
  resolved+=("$package=$candidate")
  printf '%s=%s\n' "$package" "$candidate" >> out/linux_amd64/package-inputs.txt
done
sudo apt-get --print-uris install --yes --no-install-recommends "${resolved[@]}" | tee out/linux_amd64/package-uris.txt > /dev/null
sudo apt-get install --yes --no-install-recommends "${resolved[@]}"
python3 scripts/toolchain_versions.py --platform linux_amd64 --llvm-config /usr/bin/llvm-config-19 --cxx /usr/bin/clang++-19
dpkg-query -W "${packages[@]}" > out/linux_amd64/package-installed.txt
