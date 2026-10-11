#!/usr/bin/env python3
"""Check exact platform pins against real compiler version output."""
import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROFILE_KEYS = {'linux_amd64': 'linux', 'darwin_arm64': 'macos'}
CLANG_VERSION = re.compile(r'\bclang version (\d+\.\d+\.\d+)\b')
LLVM_MISMATCH = 'llvm_version_mismatch'
CLANG_MISMATCH = 'clang_version_mismatch'
INVALID_CLANG = 'unrecognized clang version output'


@dataclass(frozen=True)
class Versions:
    llvm: str
    clang: str


class ToolchainMismatch(ValueError):
    pass


def verify_versions(actual: Versions, expected: Versions) -> None:
    verify_llvm(actual, expected)
    verify_clang(actual, expected)


def verify_llvm(actual: Versions, expected: Versions) -> None:
    if not equal_values(actual.llvm, expected.llvm):
        raise ToolchainMismatch(LLVM_MISMATCH)


def verify_clang(actual: Versions, expected: Versions) -> None:
    if not equal_values(actual.clang, expected.clang):
        raise ToolchainMismatch(CLANG_MISMATCH)


def equal_values(first: str, second: str) -> bool:
    return first == second


def select_profile(lock: dict, platform: str) -> Versions:
    profile = lock[PROFILE_KEYS[platform]]
    return Versions(profile['llvm_version'], profile['clang_version'])


def read_text(path: Path) -> str:
    return path.read_text()


def parse_json(text: str) -> dict:
    return json.loads(text)


def read_version(executable: Path) -> str:
    return subprocess.check_output([str(executable), '--version'], text=True).strip()


def parse_clang_version(output: str) -> str:
    match = CLANG_VERSION.search(output)
    if match is None:
        raise ValueError(INVALID_CLANG)
    return match.group(1)


def write_line(text: str) -> None:
    print(text)


# Effectful CLI bootstrap stays outside the pure validation functions.
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True, choices=PROFILE_KEYS)
    parser.add_argument('--llvm-config', required=True, type=Path)
    parser.add_argument('--cxx', required=True, type=Path)
    arguments = parser.parse_args()
    observed = Versions(read_version(arguments.llvm_config),
                        parse_clang_version(read_version(arguments.cxx)))
    expected = select_profile(parse_json(read_text(ROOT / 'toolchain/odin.lock.json')),
                              arguments.platform)
    verify_versions(observed, expected)
    write_line(str(observed))
