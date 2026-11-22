#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ODIN_ROOT="$PWD/.local/toolchains/odin-linux_amd64"
export PATH="$ODIN_ROOT:$("$LLVM_CONFIG" --bindir):$PATH"
python3 scripts/assert_toolchain.py linux_amd64
out="$PWD/out/linux_amd64/reconcile"
mkdir -p "$out"
sqlite="$PWD/.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64"
test -f "$sqlite/libsqlite3.a"
clang-19 -std=c11 -O2 -Wall -Wextra -Werror -c src/runtime/client/socket.c -o "$out/socket.o"
llvm-ar-19 rcsD "$out/libwb_runtime_client.a" "$out/socket.o"
build=(odin build cmd/reconcile-custody -target:linux_amd64 -vet -warnings-as-errors
       "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${build[@]}" "-out:$out/reconcile-custody"
"${build[@]}" -define:WARBAND_TEST_STOP_AFTER_COMMIT=true "-out:$out/reconcile-custody-stop-after-commit"
"${build[@]}" -define:WARBAND_TEST_STOP_BEFORE_ACK=true "-out:$out/reconcile-custody-stop-before-ack"
"${build[@]}" -define:WARBAND_TEST_STOP_BEFORE_PREPARE=true "-out:$out/reconcile-custody-stop-before-prepare"
sha256sum "$out/reconcile-custody-stop-before-prepare"
sha256sum "$out/reconcile-custody" "$out/reconcile-custody-stop-after-commit" "$out/reconcile-custody-stop-before-ack"

gate=(odin build cmd/noop-gate -target:linux_amd64 -vet -warnings-as-errors
      "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${gate[@]}" "-out:$out/noop-gate"
"${gate[@]}" -define:WARBAND_TEST_CLAIM_BARRIER=true "-out:$out/noop-gate-proof"
sha256sum "$out/noop-gate" "$out/noop-gate-proof"

accept=(odin build cmd/accept-noop -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${accept[@]}" "-out:$out/accept-noop"
"${accept[@]}" -define:WARBAND_TEST_ACCEPT_BARRIER=true "-out:$out/accept-noop-proof"

replay=(odin build cmd/replay-noop -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${replay[@]}" "-out:$out/replay-noop"
"${replay[@]}" -define:WARBAND_REPLAY_LIVE_COMPARE=true "-out:$out/replay-noop-proof"
