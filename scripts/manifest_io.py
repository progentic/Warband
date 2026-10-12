"""Acquire build observations and publish evidence at the technical boundary."""
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from manifest_rules import BuildManifest, RunnerObservation

LINUX_PLATFORM = 'linux_amd64'
LINK_COMMANDS = {LINUX_PLATFORM: 'ldd', 'darwin_arm64': 'otool'}
LLVM_KEY = 'LLVM_CONFIG'
CXX_KEY = 'CXX'


@dataclass(frozen=True)
class InspectionPaths:
    platform: str
    binary: Path
    odin: Path
    lock: Path
    manifest: Path


def inspection_paths(root: Path, platform: str) -> InspectionPaths:
    output = root / 'out' / platform
    source = root / '.local/toolchains' / ('odin-' + platform)
    return InspectionPaths(platform, output / 'warband', source / 'odin',
                           root / 'toolchain/odin.lock.json', output / 'build-manifest.json')


def executable_identity(binary: Path) -> str:
    return capture(['file', '-b', str(binary)])


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


def capture_version(executable) -> str:
    return capture([str(executable), '--version'])


def capture_odin_version(executable: Path) -> str:
    return capture([str(executable), 'version'])


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


def verified_message(identity: str) -> str:
    return 'Artifact architecture verified: ' + identity


def read_environment(name: str) -> str:
    return os.environ[name]


def read_platform_argument() -> str:
    return sys.argv[1]
