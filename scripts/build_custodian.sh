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
for variant in normal dirsync-fault publish-{1..4} pending-0 pending-83 committed-{1..4} admin-{1..5} append-{1,2}-{1,2,3} publish-err-{1..5}; do
    dest="$out/$variant"
    mkdir -p "$dest"
    flags=()
    if [[ "$variant" == dirsync-fault ]]; then flags+=(-DWB_TEST_DIRSYNC_FAILURE); fi
    if [[ "$variant" == publish-[1-4] ]]; then flags+=("-DWB_TEST_PUBLISH_STOP=${variant#publish-}"); fi
    if [[ "$variant" == publish-err-* ]]; then flags+=("-DWB_TEST_HEAD_ERROR=${variant#publish-err-}"); fi
    if [[ "$variant" == pending-* ]]; then flags+=("-DWB_TEST_PENDING_BYTES=${variant#pending-}"); fi
    if [[ "$variant" == committed-* ]]; then flags+=("-DWB_TEST_COMMITTED_STOP=${variant#committed-}"); fi
    if [[ "$variant" == admin-* ]]; then flags+=("-DWB_TEST_ADMIN_STOP=${variant#admin-}"); fi
    if [[ "$variant" == append-* ]]; then
        IFS=- read -r _ kind mode <<< "$variant"
        flags+=("-DWB_TEST_APPEND_KIND=$kind" "-DWB_TEST_APPEND_MODE=$mode")
    fi
    clang-19 -std=c11 -O2 -Wall -Wextra -Werror "${flags[@]}" -c src/custody/linux/native.c -o "$dest/native.o"
    llvm-ar-19 rcs "$dest/libwarband_custody.a" "$dest/native.o"
    odin build cmd/custodian -target:linux_amd64 -vet -warnings-as-errors "-extra-linker-flags:-L$dest" "-out:$dest/custodian"
    sha256sum "$dest/custodian"
done
