#!/usr/bin/env python3
"""Connect artifact inspection, pure manifest rules, and evidence output."""
from document_io import project_root
from manifest_io import (
    CXX_KEY, LLVM_KEY, capture_odin_version, capture_version, executable_identity, inspection_paths,
    inspect_elf_header, inspect_linkage, inspect_runner, parse_json, read_bytes,
    read_environment, read_platform_argument, read_text, hash_bytes,
    manifest_record, serialize_json, verified_message, write_line, write_text,
)
from manifest_rules import (
    assemble_artifact, assemble_build_observation, describe_compiler,
    construct_manifest, validate_architecture, validate_machine, validate_platform,
)


def main() -> None:
    platform = read_platform_argument()
    validate_platform(platform)
    paths = inspection_paths(project_root(__file__), platform)
    artifact = acquire_artifact(paths)
    validate_architecture(artifact)
    validate_machine(artifact)
    observation = acquire_build_observation(paths, artifact)
    manifest = construct_manifest(observation)
    publish_verified_manifest(paths, manifest)


def acquire_artifact(paths):
    identity = executable_identity(paths.binary)
    header = inspect_elf_header(paths.platform, paths.binary)
    return assemble_artifact(paths.platform, identity, header)


def acquire_build_observation(paths, artifact):
    linkage = inspect_linkage(paths.platform, paths.binary)
    compiler = acquire_compiler_provenance(paths)
    digest = hash_bytes(read_bytes(paths.binary))
    runner = inspect_runner()
    return assemble_build_observation(artifact, linkage, compiler, digest, runner)


def acquire_compiler_provenance(paths):
    lock = parse_json(read_text(paths.lock))
    odin = capture_odin_version(paths.odin)
    llvm = capture_version(read_environment(LLVM_KEY))
    cxx = capture_version(read_environment(CXX_KEY))
    return describe_compiler(lock, odin, llvm, cxx)


def publish_verified_manifest(paths, manifest) -> None:
    record = manifest_record(manifest)
    text = serialize_json(record)
    write_text(paths.manifest, text)
    write_line(verified_message(manifest.architecture))


if __name__ == '__main__':
    main()
