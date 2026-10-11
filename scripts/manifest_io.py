"""Acquire build observations and publish evidence at the technical boundary."""
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import subprocess

from manifest_rules import ArtifactObservation, BuildManifest, BuildObservation, RunnerObservation

LINUX_PLATFORM = 'linux_amd64'
LINK_COMMANDS = {LINUX_PLATFORM: 'ldd', 'darwin_arm64': 'otool'}


def inspect_artifact(root: Path, platform: str) -> ArtifactObservation:
    binary = root / 'out' / platform / 'warband'
    return ArtifactObservation(platform, capture(['file', '-b', str(binary)]),
                               inspect_elf_header(platform, binary))


def inspect_build(root: Path, artifact: ArtifactObservation) -> BuildObservation:
    binary = root / 'out' / artifact.platform / 'warband'
    source = root / '.local/toolchains' / ('odin-' + artifact.platform)
    lock = parse_json(read_text(root / 'toolchain/odin.lock.json'))
    return BuildObservation(
        artifact, inspect_linkage(artifact.platform, binary),
        lock['commit'], capture([str(source / 'odin'), 'version']),
        capture([os.environ['LLVM_CONFIG'], '--version']),
        capture([os.environ['CXX'], '--version']), hash_bytes(read_bytes(binary)), inspect_runner(),
    )


def publish_manifest(root: Path, platform: str, manifest: BuildManifest) -> None:
    destination = root / 'out' / platform / 'build-manifest.json'
    write_text(destination, serialize_json(manifest_record(manifest)))
    write_line('Artifact architecture verified: ' + manifest.architecture)


def inspect_elf_header(platform: str, binary: Path) -> str:
    if platform == LINUX_PLATFORM:
        return capture(['readelf', '-h', str(binary)])
    return ''


def inspect_linkage(platform: str, binary: Path) -> str:
    command = [LINK_COMMANDS[platform]]
    if platform != LINUX_PLATFORM:
        command.append('-L')
    return capture([*command, str(binary)])


def inspect_runner() -> RunnerObservation:
    return RunnerObservation(os.environ.get('GITHUB_ACTIONS') == 'true',
                             os.environ.get('ImageOS'), os.environ.get('ImageVersion'))


def parse_json(text: str) -> dict:
    return json.loads(text)


def read_text(path: Path) -> str:
    return path.read_text()


def read_bytes(path: Path) -> bytes:
    return path.read_bytes()


def hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def serialize_json(record: dict) -> str:
    return json.dumps(record, indent=2) + '\n'


def manifest_record(manifest: BuildManifest) -> dict:
    return asdict(manifest)


def capture(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def write_text(path: Path, text: str) -> None:
    path.write_text(text)


def write_line(text: str) -> None:
    print(text)
