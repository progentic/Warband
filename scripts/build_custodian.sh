#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export LLVM_CONFIG=/usr/bin/llvm-config-19
export ODIN_ROOT="$PWD/.local/toolchains/odin-linux_amd64"
export PATH="$ODIN_ROOT:$("$LLVM_CONFIG" --bindir):$PATH"
python3 scripts/assert_toolchain.py linux_amd64
out="$PWD/out/linux_amd64/custodian"
mkdir -p "$out"
# Fault variant is built separately; the production binary has no runtime fault switch.
for variant in normal dirsync-fault publish-{1..4}; do
    dest="$out/$variant"
    mkdir -p "$dest"
    flags=()
    if [[ "$variant" == dirsync-fault ]]; then flags+=(-DWB_TEST_DIRSYNC_FAILURE); fi
    if [[ "$variant" == publish-* ]]; then flags+=("-DWB_TEST_PUBLISH_STOP=${variant#publish-}"); fi
    clang-19 -std=c11 -O2 -Wall -Wextra -Werror "${flags[@]}" -c src/custody/linux/native.c -o "$dest/native.o"
    llvm-ar-19 rcs "$dest/libwarband_custody.a" "$dest/native.o"
    odin build cmd/custodian -target:linux_amd64 -vet -warnings-as-errors "-extra-linker-flags:-L$dest" "-out:$dest/custodian"
    sha256sum "$dest/custodian"
done
