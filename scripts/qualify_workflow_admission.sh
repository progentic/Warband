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

# Stop the live issuer after SQLite commits either review event to exercise receipt recovery.
export ODIN_ROOT="$PWD/.local/toolchains/odin-linux_amd64"
export PATH="$ODIN_ROOT:$("$LLVM_CONFIG" --bindir):$PATH"
sqlite="$PWD/.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64"
for kind in 12 13; do
    "$ODIN_ROOT/odin" build cmd/model-request -target:linux_amd64 -vet -warnings-as-errors \
        -define:WARBAND_REQUEST_PROOF=true "-define:WARBAND_DECISION_COMMIT_STOP=$kind" \
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out/reconcile" \
        "-out:$out/reconcile/model-request-proof-commit$kind"
done
mkdir "$evidence/traces"
install_dir=$(sudo mktemp -d /run/warband-workflow.XXXXXXXX)
trap 'sudo rm -f "$install_dir/driver"; sudo rmdir "$install_dir"' EXIT
sudo install -m555 "$out/provider/transport-connector" "$install_dir/driver"
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
    unshare --net strace -ff -qq -o "$evidence/traces/trace" -e trace=process \
    /usr/bin/python3 -u tests/integration/linux/test_workflow_admission.py "$install_dir/driver" \
    | tee "$evidence/cases.jsonl"
sudo /usr/bin/python3 tests/integration/linux/test_workflow_admission.py --grade-launches "$evidence" \
    | tee "$evidence/launches.json"
{
    uname -srmo
    sha256sum src/runtime/{marker_decision,model_request}_linux.odin cmd/{model-request,marker-approval}/main_linux.odin \
        tests/integration/linux/{test_marker_approval,test_provider_transport,test_workflow_admission}.py \
        scripts/qualify_workflow_admission.sh "$out/reconcile"/model-request{,-proof,-proof-commit12,-proof-commit13} "$out/reconcile/marker-approval" \
        "$out/provider/transport-connector" "$evidence"/{cases.jsonl,launches.json}
} | tee "$evidence/identity.txt"
