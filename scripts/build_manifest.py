#!/usr/bin/env python3
"""Inspect artifact architecture and retain the actual build provenance."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main(platform: str):
    binary = ROOT / 'out' / platform / 'warband'
    identity = capture(['file', '-b', str(binary)])
    verify_architecture(platform, identity)
    linkage = inspect_linkage(platform, binary)
    lock = json.loads((ROOT / 'toolchain/odin.lock.json').read_text())
    source = ROOT / '.local/toolchains' / ('odin-' + platform)
    runner_image, runner_version = read_runner_identity()
    manifest = {
        'odin_sha': lock['commit'], 'odin_version': capture([str(source / 'odin'), 'version']),
        'llvm_version': capture([os.environ['LLVM_CONFIG'], '--version']),
        'cxx_version': capture([os.environ['CXX'], '--version']), 'platform': platform,
        'runner_image': runner_image,
        'runner_image_version': runner_version,
        'flags': ['-vet', '-warnings-as-errors', '-target:' + platform],
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'architecture': identity, 'linkage': linkage,
    }
    (binary.parent / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Artifact architecture verified: ' + identity)


def verify_architecture(platform: str, identity: str):
    expected = {'linux_amd64': ('ELF 64-bit', 'x86-64'), 'darwin_arm64': ('Mach-O 64-bit', 'arm64')}
    if platform not in expected:
        raise ValueError('unsupported build platform')
    if any(part not in identity for part in expected[platform]):
        raise ValueError('unexpected executable architecture: ' + identity)


def inspect_linkage(platform: str, binary: Path):
    if platform == 'linux_amd64':
        header = capture(['readelf', '-h', str(binary)])
        if 'Advanced Micro Devices X86-64' not in header:
            raise ValueError('readelf machine identity mismatch')
        return capture(['ldd', str(binary)])
    return capture(['otool', '-L', str(binary)])


def read_runner_identity():
    image = os.environ.get('ImageOS')
    version = os.environ.get('ImageVersion')
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        if not image or not version:
            raise ValueError('hosted runner image identity is missing')
        return image, version
    return 'local', 'local'


def capture(command):
    return subprocess.check_output(command, text=True).strip()


if __name__ == '__main__':
    main(sys.argv[1])
