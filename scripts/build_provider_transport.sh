#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ODIN_ROOT="$PWD/.local/toolchains/odin-linux_amd64"
export PATH="$ODIN_ROOT:/usr/lib/llvm-19/bin:$PATH"
python3 scripts/assert_toolchain.py linux_amd64
out="$PWD/out/linux_amd64/provider"
mkdir -p "$out"
linkdir="$(mktemp -d)"
trap 'rm -rf "$linkdir"' EXIT
ln -s /usr/lib/x86_64-linux-gnu/libcurl.so.4 "$linkdir/libcurl.so"
ln -s /usr/lib/x86_64-linux-gnu/libz.so.1 "$linkdir/libz.so"
clang-19 -std=c11 -O2 -Wall -Wextra -Werror -c cmd/provider-transport/network_policy.c -o "$linkdir/policy.o"
llvm-ar-19 rcsD "$linkdir/libwb_network_policy.a" "$linkdir/policy.o"
for profile in fixture production-roots connector connector-production-roots; do
    test_roots=false
    if [[ $profile != *production-roots ]]; then test_roots=true; fi
    connector=false; if [[ $profile == connector* ]]; then connector=true; fi
    exe="$out/transport-$profile"
    odin build cmd/provider-transport -target:linux_amd64 -define:WARBAND_TRANSPORT_FIXTURE=true \
        "-define:WARBAND_EXTERNAL_CONNECTOR=$connector" "-define:WARBAND_TEST_ROOTS=$test_roots" -vet -warnings-as-errors "-extra-linker-flags:-L$linkdir" "-out:$exe"
    {
        uname -srmo
        sha256sum cmd/provider-transport/network_policy.c cmd/provider-transport/*.odin scripts/build_provider_transport.sh tests/integration/linux/test_provider_transport.py
        "$exe" --identity
        "$exe" --test-callbacks
        ldd "$exe"
        library=$(ldd "$exe" | awk '$1 == "libcurl.so.4" { print $3 }')
        test -f "$library"
        readelf -n "$library" | grep 'Build ID:'
        dpkg-query -W -f='${binary:Package} ${Version} ${source:Package} ${source:Version}\n' libcurl4t64 ca-certificates
        sha256sum "$exe" "$library" /etc/ssl/certs/ca-certificates.crt
        printf 'effective production trust-directory inventory SHA-256: '
        (cd /etc/ssl/certs && find -L . -maxdepth 1 -type f -name '*.[0-9]*' -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum) | sha256sum
    } | tee "$out/$profile-identity.txt"
done
if [[ ${1:-} == --qualify ]]; then
    : "${2:?supply retained Go crypto/x509/verify_test.go for offline chain verification}"
    test "$(uname -r)" = 6.8.0-142-generic
    dest=$(sudo mktemp -d /run/warband-provider.XXXXXXXX)
    trap 'rm -rf "$linkdir"; sudo rm -f "$dest/driver"; sudo rmdir "$dest"' EXIT
    for profile in fixture production-roots; do
        sudo install -m 555 "$out/transport-$profile" "$dest/driver"
        opts=()
        if [[ $profile == production-roots ]]; then opts=(--production-roots --public-vectors "$2"); fi
        sudo python3 tests/integration/linux/test_provider_transport.py --trusted-launcher "$dest/driver" "${opts[@]}" | tee "$out/$profile-results.jsonl"
    done
fi
