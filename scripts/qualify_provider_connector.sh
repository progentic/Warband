#!/usr/bin/env bash
# Run on the isolated, preproduction x64-review target with the pinned toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -mr)" = "6.8.0-142-generic x86_64"
export LLVM_CONFIG=/usr/bin/llvm-config-19
out="$PWD/out/linux_amd64/provider"
mkdir -p "$out"
evidence=$(mktemp -d "$out/connector-142.XXXXXXXX")
bash scripts/build_provider_transport.sh > "$evidence/build.log"
bash scripts/test_writer_open.sh linux_amd64 > "$evidence/store.log"
bash scripts/build_custodian.sh > "$evidence/custodian.log"
bash scripts/build_reconcile.sh > "$evidence/runtime.log"
install_dir=$(sudo mktemp -d /run/warband-connector.XXXXXXXX)
trap 'sudo rm -f "$install_dir/driver"; sudo rmdir "$install_dir"' EXIT
sudo install -m555 "$out/transport-connector" "$install_dir/driver"
mkdir "$evidence/traces"
sudo strace -ff -o "$evidence/traces/trace" -e trace=socket,connect,prctl,setresuid,unshare \
    unshare --net /usr/bin/python3 -u tests/integration/linux/test_provider_connector.py "$install_dir/driver" \
    | tee "$evidence/cases.jsonl"
sudo /usr/bin/python3 tests/integration/linux/test_provider_connector.py --verify-traces "$evidence/traces" "$evidence/cases.jsonl" \
    | tee "$evidence/kernel.json"
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
    /usr/bin/python3 tests/integration/linux/test_marker_worker.py > "$evidence/worker.log" 2>&1
{
    uname -srmo
    sha256sum "$out/transport-connector" out/linux_amd64/reconcile/{marker-approval,marker-worker,marker-supervisor,worker-probe}
    sha256sum cmd/provider-transport/* scripts/{build_provider_transport,qualify_provider_connector}.sh tests/integration/linux/{test_provider_connector,test_marker_worker}.py
    sha256sum "$evidence"/{cases.jsonl,kernel.json,worker.log}
} | tee "$evidence/identity.txt"
