#!/usr/bin/env python3
"""Verify the compiler source, executable, resource tree, and reported revision."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def verify(platform: str):
    lock = json.loads((ROOT / 'toolchain/odin.lock.json').read_text())
    source = ROOT / '.local/toolchains' / ('odin-' + platform)
    compiler = source / 'odin'
    if Path(shutil.which('odin') or '').resolve() != compiler.resolve():
        raise ValueError('PATH does not resolve to the project compiler')
    head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if head != lock['commit']:
        raise ValueError('compiler source revision mismatch')
    version = subprocess.check_output([str(compiler), 'version'], text=True)
    if lock['commit'][:7] not in version:
        raise ValueError('compiler version omits expected source revision')
    if Path(os.environ.get('ODIN_ROOT', '')).resolve() != source.resolve():
        raise ValueError('ODIN_ROOT differs from pinned source tree')
    for name in ('base', 'core', 'vendor'):
        if not (source / name).is_dir():
            raise ValueError('compiler resource directory missing: ' + name)
    print('Compiler identity verified: ' + lock['commit'])


if __name__ == '__main__':
    verify(sys.argv[1])
