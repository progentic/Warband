#!/usr/bin/env python3
"""Smoke-test the actual executable's output and rejected command behavior."""
from pathlib import Path
import subprocess
import sys

VERSION = 'Warband Phase 1 foundation (no execution authority)\n'
FIXTURE = '[01, 01, 00, 00, 00, 00, 00, 00, 00, 02, 00, 00, 00, 00, 00, 00, 00, 03, 00, 00, 00, 00, 00, 00, 00]\n'
USAGE = 'usage: warband version | fixture\n'


def verify(binary: Path):
    for command, output in (('version', VERSION), ('fixture', FIXTURE)):
        result = run(binary, (command,))
        if (result.returncode, result.stdout, result.stderr) != (0, output, ''):
            raise ValueError('unexpected CLI behavior: ' + command)
    for arguments in ((), ('execute',), ('fixture', 'extra')):
        result = run(binary, arguments)
        if (result.returncode, result.stdout, result.stderr) != (2, '', USAGE):
            raise ValueError('unsupported command was not safely rejected')
    print('CLI smoke passed: version, fixed bytes, and 3 rejected argument forms.')


def run(binary: Path, arguments):
    return subprocess.run([str(binary.resolve()), *arguments], text=True,
                          capture_output=True, timeout=10, check=False)


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
