"""Independent observations exercise manifest acceptance and rejection."""
from dataclasses import replace
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from manifest_rules import (
    ArtifactObservation, BuildObservation, ManifestRejected, RunnerObservation,
    construct_manifest,
)

LINUX = ArtifactObservation('linux_amd64', 'ELF 64-bit LSB executable, x86-64',
                            'Machine: Advanced Micro Devices X86-64')
MACOS = ArtifactObservation('darwin_arm64', 'Mach-O 64-bit executable arm64', '')
OBSERVED = BuildObservation(LINUX, 'libc.so.6', 'a' * 40, 'reviewed Odin',
                            '19.1.1', 'reviewed clang', 'b' * 64,
                            RunnerObservation(True, 'ubuntu24', 'review-image'))


class ManifestControls(unittest.TestCase):
    def test_preserves_observed_identity_and_target(self):
        for artifact in (LINUX, MACOS):
            with self.subTest(platform=artifact.platform):
                manifest = construct_manifest(replace(OBSERVED, artifact=artifact))
                self.assertEqual(manifest.platform, artifact.platform)
                self.assertEqual(manifest.architecture, artifact.architecture)
                self.assertEqual(manifest.odin_sha, 'a' * 40)
                self.assertEqual(manifest.binary_sha256, 'b' * 64)
                self.assertEqual(manifest.flags, ('-vet', '-warnings-as-errors', '-target:' + artifact.platform))
                self.assertEqual((manifest.runner_image, manifest.runner_image_version), ('ubuntu24', 'review-image'))

    def test_rejects_unsupported_platform_format_and_machine(self):
        examples = (
            replace(LINUX, platform='linux_arm64'),
            replace(LINUX, architecture='ELF 64-bit LSB executable, ARM aarch64'),
            replace(LINUX, architecture='ELF 32-bit LSB executable, x86-64'),
            replace(LINUX, elf_header='Machine: AArch64'),
            replace(MACOS, architecture='Mach-O 64-bit executable x86_64'),
        )
        for artifact in examples:
            with self.subTest(artifact=artifact), self.assertRaises(ManifestRejected):
                construct_manifest(replace(OBSERVED, artifact=artifact))

    def test_hosted_identity_cannot_fall_back_to_local(self):
        for image, version in ((None, 'review-image'), ('ubuntu24', None), ('', 'review-image'), ('ubuntu24', '')):
            runner = RunnerObservation(True, image, version)
            with self.subTest(runner=runner), self.assertRaisesRegex(ManifestRejected, 'identity is missing'):
                construct_manifest(replace(OBSERVED, runner=runner))

    def test_local_build_discards_stale_hosted_identity(self):
        runner = RunnerObservation(False, 'stale-hosted-image', 'stale-version')
        manifest = construct_manifest(replace(OBSERVED, runner=runner))
        self.assertEqual((manifest.runner_image, manifest.runner_image_version), ('local', 'local'))


if __name__ == '__main__':
    unittest.main()
