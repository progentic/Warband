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
"${build[@]}" -define:WARBAND_TEST_STOP_AFTER_PREPARE=true "-out:$out/reconcile-custody-stop-after-prepare"
"${build[@]}" -define:WARBAND_TEST_STOP_AFTER_EVENT_INSERT=true "-out:$out/reconcile-custody-stop-event-insert"
"${build[@]}" -define:WARBAND_TEST_STOP_IN_WAL_COMMIT=true "-out:$out/reconcile-custody-stop-wal-commit"
sha256sum "$out/reconcile-custody-stop-event-insert" "$out/reconcile-custody-stop-wal-commit"
sha256sum "$out/reconcile-custody-stop-before-prepare" "$out/reconcile-custody-stop-after-prepare"
sha256sum "$out/reconcile-custody" "$out/reconcile-custody-stop-after-commit" "$out/reconcile-custody-stop-before-ack"

for fault in 1 2 3; do
    "${build[@]}" "-define:WARBAND_TEST_SQLITE_FAULT=$fault" "-out:$out/reconcile-sqlite-$fault"
    sha256sum "$out/reconcile-sqlite-$fault"
done

gate=(odin build cmd/noop-gate -target:linux_amd64 -vet -warnings-as-errors
      "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${gate[@]}" "-out:$out/noop-gate"
"${gate[@]}" -define:WARBAND_TEST_CLAIM_BARRIER=true "-out:$out/noop-gate-proof"
sha256sum "$out/noop-gate" "$out/noop-gate-proof"

accept=(odin build cmd/accept-noop -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${accept[@]}" "-out:$out/accept-noop"
"${accept[@]}" -define:WARBAND_TEST_ACCEPT_BARRIER=true "-out:$out/accept-noop-proof"

# Witness primitive calls without enabling the claim/observation barriers.
"${gate[@]}" -define:WARBAND_TEST_INVOCATION_WITNESS=true "-out:$out/noop-gate-witness"
sha256sum "$out/noop-gate-witness"
for stage in insert commit; do
    flag=-define:WARBAND_TEST_STOP_AFTER_EVENT_INSERT=true
    if [[ "$stage" == commit ]]; then flag=-define:WARBAND_TEST_STOP_IN_WAL_COMMIT=true; fi
    "${gate[@]}" -define:WARBAND_TEST_INVOCATION_WITNESS=true -define:WARBAND_TEST_TRANSACTION_KIND=5 "$flag" "-out:$out/noop-gate-$stage"
    "${accept[@]}" -define:WARBAND_TEST_TRANSACTION_KIND=7 "$flag" "-out:$out/accept-noop-$stage"
    sha256sum "$out/noop-gate-$stage" "$out/accept-noop-$stage"
done

replay=(odin build cmd/replay-noop -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${replay[@]}" "-out:$out/replay-noop"
"${replay[@]}" -define:WARBAND_REPLAY_LIVE_COMPARE=true "-out:$out/replay-noop-proof"

intake=(odin build cmd/marker-intake -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${intake[@]}" "-out:$out/marker-intake"
for edge in 1 2 3 4; do
    "${intake[@]}" "-define:WARBAND_INTAKE_STOP=$edge" "-out:$out/marker-intake-$edge"
done
sha256sum "$out/marker-intake" "$out"/marker-intake-[1234]

review=(odin build cmd/marker-approval -target:linux_amd64 -vet -warnings-as-errors
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out")
"${review[@]}" "-out:$out/marker-approval"
for edge in 12 13; do
    "${review[@]}" "-define:WARBAND_DECISION_COMMIT_STOP=$edge" "-out:$out/marker-approval-$edge"
done
sha256sum "$out/marker-approval" "$out"/marker-approval-{12,13}
