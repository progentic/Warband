#!/usr/bin/env python3
"""Relocate a verified Homebrew bottle inside this project, without installing globally.

Download the bottle at the URL in toolchain/odin.lock.json before running this tool.
The only host dependency reused is the already installed Homebrew zstd library.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    lock = json.loads((ROOT / 'toolchain/odin.lock.json').read_text())
    bottle = ROOT / '.local/toolchains/llvm19.tar.gz'
    with bottle.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != lock['macos']['bottle_sha256']:
        raise ValueError('Homebrew LLVM bottle checksum mismatch')
    prefix = ROOT / '.local/toolchains/llvm@19' / lock['macos']['llvm_version']
    zstd = Path(capture(['brew', '--prefix', 'zstd'])) / 'lib/libzstd.1.dylib'
    if not zstd.is_file():
        raise ValueError('Homebrew zstd must already be installed')
    extract_bottle(bottle, prefix)
    relocate(prefix, zstd)
    print(capture([str(prefix / 'bin/llvm-config'), '--version']))
    print(capture(['brew', 'list', '--versions', 'zstd']))


def extract_bottle(bottle: Path, prefix: Path):
    # Stage first: repeated preparation must not truncate read-only cache files.
    with tempfile.TemporaryDirectory(dir=ROOT / '.local/toolchains') as temporary:
        with tarfile.open(bottle) as archive:
            archive.extractall(temporary, filter='data')
        staged = Path(temporary) / 'llvm@19' / prefix.name
        if prefix.exists():
            shutil.rmtree(prefix)
        prefix.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(staged, prefix)


def relocate(prefix: Path, zstd: Path):
    paths = (prefix / 'bin/llvm-config', prefix / 'lib/libLLVM.dylib')
    for path in paths:
        execute(['install_name_tool', '-change',
                 '@@HOMEBREW_PREFIX@@/opt/zstd/lib/libzstd.1.dylib', str(zstd), str(path)])
    library = prefix / 'lib/libLLVM.dylib'
    execute(['install_name_tool', '-id', str(library), str(library)])
    for path in paths:
        execute(['codesign', '--force', '--sign', '-', str(path)])


def capture(command):
    return subprocess.check_output(command, text=True).strip()


def execute(command):
    subprocess.run(command, check=True)


if __name__ == '__main__':
    main()
