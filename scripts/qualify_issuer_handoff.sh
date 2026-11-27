#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -mr)" = "6.8.0-142-generic x86_64"
tree() {
    git diff --quiet && test -z "$(git ls-files --others --exclude-standard)" &&
        test -z "$(git ls-files --others -- src cmd)" && git write-tree
}
source_tree=$(tree)
export LLVM_CONFIG=/usr/bin/llvm-config-19
out="$PWD/out/linux_amd64"
mkdir -p "$out/provider"
evidence=$(mktemp -d "$out/provider/issuer-142.XXXXXXXX")
echo "Evidence directory: $evidence"
bash scripts/test_writer_open.sh linux_amd64 > "$evidence/store.log" 2>&1
bash scripts/build_custodian.sh > "$evidence/custodian.log" 2>&1
bash scripts/build_reconcile.sh > "$evidence/runtime.log" 2>&1
bash scripts/build_provider_transport.sh --qualify-normal > "$evidence/provider.log" 2>&1
export ODIN_ROOT="$PWD/.local/toolchains/odin-linux_amd64"
export PATH="$ODIN_ROOT:$("$LLVM_CONFIG" --bindir):$PATH"
sqlite="$PWD/.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64"
for edge in retry prepared committed; do
    case "$edge" in
        retry) flag=-define:WARBAND_FAILURE_RETRY_PROOF=true ;;
        prepared) flag=-define:WARBAND_FAILURE_OBSERVATION_STOP=1 ;;
        committed) flag=-define:WARBAND_FAILURE_OBSERVATION_STOP=2 ;;
    esac
    odin build cmd/model-request -target:linux_amd64 -vet -warnings-as-errors -define:WARBAND_REQUEST_PROOF=true "$flag" \
        "-collection:warband_sqlite=$sqlite" "-extra-linker-flags:-L$out/reconcile" "-out:$out/reconcile/model-request-failure-$edge"
done
install_dir=$(sudo mktemp -d /var/lib/warband-handoff.XXXXXXXX)
trap 'sudo rm -f "$install_dir"/{provider_handoff.py,model-request,transport-normal}; sudo rmdir "$install_dir"' EXIT
sudo chmod 755 "$install_dir"
sudo install -m555 scripts/provider_handoff.py "$out/reconcile/model-request" "$out/provider/transport-normal" "$install_dir/"
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 unshare --mount --propagation private --net \
    /usr/bin/python3 -u tests/integration/linux/test_issuer_handoff.py "$install_dir" > "$evidence/cases.jsonl"
test "$(tree)" = "$source_tree"
echo "$source_tree" > "$evidence/source-tree.txt"
sha256sum "$install_dir"/* "$out/reconcile/marker-approval" "$out/reconcile"/model-request-failure-{retry,prepared,committed} "$evidence/cases.jsonl" | tee "$evidence/identity.txt"
python3 - "$evidence" <<'PYTHON'
import json,sys
from pathlib import Path
if not __debug__: raise RuntimeError('grading requires assertions')
p=Path(sys.argv[1])
rows=[json.loads(s) for s in (p/'cases.jsonl').read_text().splitlines() if s.startswith('{"case":')]
assert [r['case'] for r in rows]==['no-credential','system-roots','approve','issuer-death','courier-death','approval-after-failure']
refused,*transfers=rows
assert refused['custodian_collision']=='refused before child registration' and refused['connections']==refused['requests']==0
assert refused['terminal']=='ProviderFailure CredentialUnavailable CountsUnavailable' and refused['admissions']==refused['permits']==0
for r in transfers:
    assert r['descendants_reaped'] and r['competing_requests']==0 and r['roles_checked']==[60001,60002,60003]
    assert r['connections']==1 and r['requests']==int(r['case']!='system-roots')
    assert r['admissions']==r['permits']==int(r['case'] in ('approve','approval-after-failure'))
    assert (r['ca_bundle_sha256']==r['synthetic_leaf_sha256'])==(r['case']!='system-roots')
cases=[json.loads(s) for s in (p/'cases.jsonl').read_text().splitlines() if s.startswith('{"observation_case":')]
assert [r['observation_case'] for r in cases]==['retry','prepared','committed','tampered']
expected=[[18,20,19],[18,20,19],[18,1,11,12,13],[18,19],[18,19],[18,20,19,18,1,11,12,13],
          [18,20,19],[18],[18,20,19],[18,20]]
for r,kinds in zip(rows+cases,expected,strict=True):
    assert [bytes.fromhex(w)[6] for w in r['history']]==kinds
PYTHON
python3 tests/integration/linux/test_issuer_handoff.py --grade-histories "$evidence" | tee "$evidence/observations.json"
(cd "$evidence" && sha256sum *.log *.jsonl *.json *.txt > SHA256SUMS)
sha256sum "$evidence/SHA256SUMS"
