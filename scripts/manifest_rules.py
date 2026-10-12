"""Pure build-evidence rules; no filesystem, process, or environment access."""
from dataclasses import dataclass

LINUX_PLATFORM = 'linux_amd64'
MACOS_PLATFORM = 'darwin_arm64'
FORMAT_MARKERS = {
    LINUX_PLATFORM: ('ELF 64-bit', 'x86-64'),
    MACOS_PLATFORM: ('Mach-O 64-bit', 'arm64'),
}
ELF_MACHINE = 'Advanced Micro Devices X86-64'
LOCAL_IDENTITY = 'local'
VET_FLAGS = ('-vet', '-warnings-as-errors')
TARGET_FLAG = '-target:'
UNSUPPORTED_PLATFORM = 'unsupported build platform'
WRONG_ARCHITECTURE = 'unexpected executable architecture'
WRONG_MACHINE = 'readelf machine identity mismatch'
MISSING_RUNNER = 'hosted runner image identity is missing'
COMMIT_FIELD = 'commit'


class ManifestRejected(ValueError):
    pass


@dataclass(frozen=True)
class ArtifactObservation:
    platform: str
    architecture: str
    elf_header: str


@dataclass(frozen=True)
class RunnerObservation:
    hosted: bool
    image: str | None
    version: str | None


LOCAL_RUNNER = RunnerObservation(False, LOCAL_IDENTITY, LOCAL_IDENTITY)


@dataclass(frozen=True)
class BuildObservation:
    artifact: ArtifactObservation
    linkage: str
    odin_sha: str
    odin_version: str
    llvm_version: str
    cxx_version: str
    binary_sha256: str
    runner: RunnerObservation


@dataclass(frozen=True)
class CompilerObservation:
    odin_sha: str
    odin_version: str
    llvm_version: str
    cxx_version: str


@dataclass(frozen=True)
class BuildManifest:
    odin_sha: str
    odin_version: str
    llvm_version: str
    cxx_version: str
    platform: str
    runner_image: str | None
    runner_image_version: str | None
    flags: tuple[str, ...]
    binary_sha256: str
    architecture: str
    linkage: str


def construct_manifest(observation: BuildObservation) -> BuildManifest:
    validate_platform(observation.artifact.platform)
    validate_architecture(observation.artifact)
    validate_machine(observation.artifact)
    validate_runner_image(observation.runner)
    validate_runner_version(observation.runner)
    runner = choose_runner_identity(observation.runner)
    return describe_manifest(observation, runner)


def assemble_artifact(platform: str, identity: str, header: str) -> ArtifactObservation:
    return ArtifactObservation(platform, identity, header)


def describe_compiler(lock: dict, odin: str, llvm: str, cxx: str) -> CompilerObservation:
    return CompilerObservation(lock[COMMIT_FIELD], odin, llvm, cxx)


def assemble_build_observation(artifact, linkage, compiler, digest, runner) -> BuildObservation:
    return BuildObservation(artifact, linkage, compiler.odin_sha, compiler.odin_version,
                            compiler.llvm_version, compiler.cxx_version, digest, runner)


def validate_platform(platform: str) -> None:
    if platform not in FORMAT_MARKERS:
        raise ManifestRejected(UNSUPPORTED_PLATFORM)


def validate_architecture(artifact: ArtifactObservation) -> None:
    markers = FORMAT_MARKERS[artifact.platform]
    if not includes_markers(artifact.architecture, markers):
        raise ManifestRejected(WRONG_ARCHITECTURE, artifact.architecture)


def validate_machine(artifact: ArtifactObservation) -> None:
    if artifact.platform != LINUX_PLATFORM:
        return
    if not contains_text(artifact.elf_header, ELF_MACHINE):
        raise ManifestRejected(WRONG_MACHINE)


def validate_runner_image(runner: RunnerObservation) -> None:
    if not runner.hosted:
        return
    if not runner.image:
        raise ManifestRejected(MISSING_RUNNER)


def validate_runner_version(runner: RunnerObservation) -> None:
    if not runner.hosted:
        return
    if not runner.version:
        raise ManifestRejected(MISSING_RUNNER)


def choose_runner_identity(runner: RunnerObservation) -> RunnerObservation:
    if runner.hosted:
        return runner
    return LOCAL_RUNNER


def describe_manifest(observation: BuildObservation, runner: RunnerObservation) -> BuildManifest:
    return BuildManifest(
        odin_sha=observation.odin_sha,
        odin_version=observation.odin_version,
        llvm_version=observation.llvm_version,
        cxx_version=observation.cxx_version,
        platform=observation.artifact.platform,
        runner_image=runner.image,
        runner_image_version=runner.version,
        flags=target_flags(observation.artifact.platform),
        binary_sha256=observation.binary_sha256,
        architecture=observation.artifact.architecture,
        linkage=observation.linkage,
    )


def includes_markers(text: str, markers: tuple[str, ...]) -> bool:
    return all(marker in text for marker in markers)


def contains_text(text: str, fragment: str) -> bool:
    return fragment in text


def target_flags(platform: str) -> tuple[str, ...]:
    return (*VET_FLAGS, TARGET_FLAG + platform)
