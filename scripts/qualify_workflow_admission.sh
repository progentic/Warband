#!/usr/bin/env bash
# Run on the qualified x64-review VM with the retained Odin and SQLite inputs.
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -mr)" = "6.8.0-142-generic x86_64"
export LLVM_CONFIG=/usr/bin/llvm-config-19
out="$PWD/out/linux_amd64"
mkdir -p "$out/provider"
evidence=$(mktemp -d "$out/provider/workflow-admission.XXXXXXXX")
echo "Evidence directory: $evidence"
bash scripts/test_writer_open.sh linux_amd64 > "$evidence/store.log"
bash scripts/build_custodian.sh > "$evidence/custodian.log"
bash scripts/build_reconcile.sh > "$evidence/runtime.log"
bash scripts/build_provider_transport.sh > "$evidence/provider.log"

install_dir=$(sudo mktemp -d /run/warband-workflow.XXXXXXXX)
trap 'sudo rm -f "$install_dir/driver"; sudo rmdir "$install_dir"' EXIT
sudo install -m555 "$out/provider/transport-connector" "$install_dir/driver"
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
    unshare --net /usr/bin/python3 -u tests/integration/linux/test_workflow_admission.py "$install_dir/driver" \
    | tee "$evidence/cases.jsonl"
{
    uname -srmo
    sha256sum src/runtime/model_request_linux.odin cmd/model-request/main_linux.odin \
        tests/integration/linux/{test_provider_transport,test_workflow_admission}.py \
        scripts/qualify_workflow_admission.sh "$out/reconcile"/model-request{,-proof} \
        "$out/provider/transport-connector" "$evidence/cases.jsonl"
} | tee "$evidence/identity.txt"
