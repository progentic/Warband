#!/usr/bin/env python3
"""Connect artifact inspection, pure manifest rules, and evidence output."""
from pathlib import Path
import sys

from manifest_io import inspect_artifact, inspect_build, publish_manifest
from manifest_rules import construct_manifest, validate_architecture, validate_machine, validate_platform

ROOT = Path(__file__).resolve().parents[1]


def main(platform: str):
    validate_platform(platform)
    artifact = inspect_artifact(ROOT, platform)
    validate_architecture(artifact)
    validate_machine(artifact)
    observation = inspect_build(ROOT, artifact)
    manifest = construct_manifest(observation)
    publish_manifest(ROOT, platform, manifest)


if __name__ == '__main__':
    main(sys.argv[1])
