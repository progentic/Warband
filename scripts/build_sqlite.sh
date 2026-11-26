#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
target="${1:?usage: build_sqlite.sh linux_amd64|darwin_arm64}"
case "$(uname -s)-$(uname -m)/$target" in
    Linux-x86_64/linux_amd64)
        llvm_config=/usr/bin/llvm-config-19
        bin="$("$llvm_config" --bindir)"
        ;;
    Darwin-arm64/darwin_arm64)
        llvm_config="${LLVM_CONFIG:?select the pinned llvm-config}"
        bin="$(cd "$(dirname "$llvm_config")" && pwd)"
        SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
        export SDKROOT
        ;;
    *) echo "Unsupported native host/target: $(uname -sm) / $target" >&2; exit 1 ;;
esac
cc="$bin/clang"
ar="$bin/llvm-ar"
python3 scripts/toolchain_versions.py --platform "$target" --llvm-config "$llvm_config" --cxx "$cc"
source_id='2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76'
dest="$root/.local/dependencies/sqlite/${source_id##* }/$target"
mkdir -p "$dest"
work="$(mktemp -d "$dest/build.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$work"
url=https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' "$url" -o source.zip
python3 - "$source_id" <<'PY'
import hashlib
from pathlib import Path
import sys
import zipfile

def verify(name, data, expected):
    actual = hashlib.sha3_256(data).hexdigest()
    print(f"{name} SHA3-256: {actual}", flush=True)
    if actual != expected:
        raise SystemExit(f"{name} SHA3-256 mismatch")

archive = Path("source.zip")
verify(archive.name, archive.read_bytes(), "92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30")
with zipfile.ZipFile(archive) as bundle:
    for name in ("sqlite3.c", "sqlite3.h"):
        data = bundle.read("sqlite-amalgamation-3540100/" + name)
        if name == "sqlite3.c":
            verify(name, data, "e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81")
        definitions = [line.split(None, 2)[2] for line in data.splitlines()
                       if line.split(None, 2)[:2] == [b"#define", b"SQLITE_SOURCE_ID"]]
        if definitions != [f'"{sys.argv[1]}"'.encode()]:
            raise SystemExit(f"{name} SQLITE_SOURCE_ID mismatch")
        Path(name).write_bytes(data)
PY
flags=(-O2 -fPIC -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DQS=0)
printf 'target: %s\ncompiler: %s\nflags: %s\narchiver: %s rcsD\n' "$target" "$cc" "${flags[*]}" "$ar"
"$cc" --version
"$ar" --version
"$cc" "${flags[@]}" -c sqlite3.c -o sqlite3.o
"$ar" rcsD libsqlite3.a sqlite3.o
"$cc" -I . "$root/scripts/verify_sqlite_build.c" "$work/libsqlite3.a" -pthread -o probe
format="$(file -b probe)"
printf 'executable: %s\n' "$format"
case "$target/$format" in
    linux_amd64/ELF*64-bit*x86-64*|darwin_arm64/Mach-O*64-bit*arm64*) ;;
    *) echo "Unexpected executable architecture" >&2; exit 1 ;;
esac
shasum -a 256 sqlite3.o libsqlite3.a
if [[ "$target" == linux_amd64 ]]; then
    ldd ./probe > linkage.txt
else
    otool -L ./probe > linkage.txt
fi
cat linkage.txt
if grep -Ei 'libsqlite[^ /]*\.(so|dylib)' linkage.txt; then
    echo "Unexpected dynamic SQLite linkage" >&2
    exit 1
fi
./probe "$source_id"
mv libsqlite3.a "$dest/libsqlite3.a"
printf 'Verified static archive: %s/libsqlite3.a\n' "$dest"
