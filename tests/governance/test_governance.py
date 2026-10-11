"""Real repository fixtures exercise fail-closed phase and baseline checks."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from document_io import read_inventory
from governance import validate_inventory


class GovernanceTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(dir=ROOT / '.local')
        self.root = Path(self.scratch.name)
        # Use tracked documentation; CI does not contain the ignored input ZIP tree.
        for name in ('docs', 'vm', '.agents'):
            shutil.copytree(ROOT / name, self.root / name)
        for path in ROOT.glob('*.md'):
            shutil.copy2(path, self.root / path.name)
        shutil.copy2(ROOT / 'LICENSE', self.root / 'LICENSE')
        self.declare_phase(0)

    def tearDown(self):
        self.scratch.cleanup()

    def declare_phase(self, phase):
        (self.root / 'project.json').write_text(json.dumps({'phase': phase}))

    def codes(self):
        return {finding.code for finding in validate_inventory(read_inventory(self.root))}

    def test_phase_zero_baseline_passes(self):
        self.assertEqual(self.codes(), set())

    def test_phase_zero_rejects_source(self):
        (self.root / 'src').mkdir()
        self.assertIn('premature_runtime', self.codes())

    def test_phase_one_allows_source(self):
        self.declare_phase(1)
        (self.root / 'src').mkdir()
        (self.root / 'cmd').mkdir()
        self.assertEqual(self.codes(), set())

    def test_invalid_phase_values_fail_closed(self):
        for value in (2, -1, True, 1.0, '1', None):
            with self.subTest(value=value):
                self.declare_phase(value)
                self.assertIn('invalid_phase', self.codes())
        for text in ('{', '{"phase":0,"phase":1}', '{"phase":1,"bypass":true}'):
            (self.root / 'project.json').write_text(text)
            self.assertIn('invalid_phase', self.codes())

    def test_missing_phase_fails(self):
        (self.root / 'project.json').unlink()
        self.assertIn('invalid_phase', self.codes())
        self.assertIn('missing_required_file', self.codes())

    def test_phase_one_cannot_bypass_required_contracts(self):
        self.declare_phase(1)
        (self.root / 'docs/contracts/authoritative-state.md').unlink()
        self.assertIn('missing_required_file', self.codes())

    def test_symlinked_phase_cannot_read_external_declaration(self):
        path = self.root / 'project.json'
        path.unlink()
        path.symlink_to(ROOT / 'project.json')
        self.assertIn('invalid_phase', self.codes())
        self.assertIn('symlinked_input', self.codes())

    def test_missing_contract_heading_fails(self):
        path = self.root / 'docs/contracts/model-proposals.md'
        path.write_text(path.read_text().replace('## Security contract', '## Removed'))
        self.assertIn('missing_contract_heading', self.codes())

    def test_escape_and_broken_links_fail(self):
        (self.root / 'README.md').write_text('[escape](../outside)\n[missing](absent.md)')
        self.assertIn('link_escapes_repository', self.codes())
        self.assertIn('broken_link', self.codes())

    def test_override_and_bad_skill_fail(self):
        nested = self.root / 'docs/build'
        nested.mkdir()
        (nested / 'AGENTS.override.md').write_text('override')
        (self.root / '.agents/skills/warband-governance-review/SKILL.md').write_text('invalid')
        self.assertIn('unexpected_override', self.codes())
        self.assertIn('invalid_skill_frontmatter', self.codes())

    def test_guidance_limit_and_traceability_fail(self):
        (self.root / 'AGENTS.md').write_text('x' * 32769)
        path = self.root / 'docs/verification/traceability-matrix.md'
        path.write_text(path.read_text().replace('WB-CON-001', 'WB-CON-999'))
        self.assertIn('guidance_size_limit', self.codes())
        self.assertIn('unmapped_constitution_id', self.codes())
        self.assertIn('undefined_constitution_id', self.codes())


if __name__ == '__main__':
    unittest.main()
