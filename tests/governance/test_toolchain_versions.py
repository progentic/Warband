"""Exercise the wired exact-version gate with independent tool output fixtures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ToolchainVersionControls(unittest.TestCase):
    def test_platform_pins_pass_and_wrong_patch_fails(self):
        examples = (
            ('linux_amd64', '19.1.1', '19.1.1', True),
            ('darwin_arm64', '19.1.7', '19.1.7', True),
            ('linux_amd64', '19.1.7', '19.1.1', False),
            ('linux_amd64', '19.1.1', '19.1.7', False),
            ('darwin_arm64', '19.1.1', '19.1.7', False),
            ('darwin_arm64', '19.1.7', '19.1.70', False),
        )
        for platform, llvm, clang, permitted in examples:
            with self.subTest(platform=platform, llvm=llvm, clang=clang):
                result = self.check(platform, llvm, 'Ubuntu clang version ' + clang)
                self.assertEqual(result.returncode == 0, permitted, result.stderr)

    def test_unrecognized_clang_output_fails(self):
        result = self.check('linux_amd64', '19.1.1', 'not a compiler version')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unrecognized clang version output', result.stderr)

    def check(self, platform, llvm, clang):
        with tempfile.TemporaryDirectory(dir=ROOT / '.local') as temporary:
            directory = Path(temporary)
            config = directory / 'llvm-config'
            compiler = directory / 'clang++'
            config.write_text('#!/bin/sh\nprintf "%s\\n" "' + llvm + '"\n')
            compiler.write_text('#!/bin/sh\nprintf "%s\\n" "' + clang + '"\n')
            config.chmod(0o755)
            compiler.chmod(0o755)
            return subprocess.run([
                'python3', str(ROOT / 'scripts/toolchain_versions.py'),
                '--platform', platform, '--llvm-config', str(config), '--cxx', str(compiler),
            ], text=True, capture_output=True, check=False)
