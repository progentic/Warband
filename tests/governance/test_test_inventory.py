"""Controls prove that omission and falsely green reports fail verification."""
from pathlib import Path
import json
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from run_odin_tests import discover_packages, read_manifest
from test_inventory import validate_packages, validate_report


class TestInventoryControls(unittest.TestCase):
    def setUp(self):
        self.declared = read_manifest(ROOT / 'tests/odin-packages.json')
        self.discovered = discover_packages(ROOT / 'tests/odin')

    def test_current_manifest_matches_source_inventory(self):
        validate_packages(self.declared, self.discovered)

    def test_manifest_requires_matching_known_project_phase(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.local') as directory:
            project = Path(directory) / 'project.json'
            manifest = Path(directory) / 'packages.json'
            project.write_text('{"phase":2}')
            value = json.loads((ROOT / 'tests/odin-packages.json').read_text())
            manifest.write_text(json.dumps(dict(value, phase=2)))
            self.assertEqual(read_manifest(manifest, project), self.declared)
            for phase in (1, 3, True):
                manifest.write_text(json.dumps(dict(value, phase=phase)))
                with self.subTest(phase=phase), self.assertRaises(ValueError):
                    read_manifest(manifest, project)
            manifest.write_text('{"phase":2,"phase":2,"packages":[]}')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                read_manifest(manifest, project)

    def test_omitting_required_package_fails(self):
        with self.assertRaisesRegex(ValueError, 'differs'):
            validate_packages(self.declared[:-1], self.discovered)

    def test_deleting_required_package_fails(self):
        with self.assertRaisesRegex(ValueError, 'differs'):
            validate_packages(self.declared, self.discovered[:-1])

    def test_zero_and_wrong_count_reports_fail(self):
        package = self.declared[0]
        tests = [{'name': name, 'success': True} for name in package.names]
        report = {'packages': {'foundation_test': tests}, 'total': len(tests), 'success': len(tests)}
        validate_report(package, report)
        for total in (0, len(tests) + 1):
            with self.subTest(total=total), self.assertRaises(ValueError):
                validate_report(package, dict(report, total=total))
        tests[0]['success'] = False
        with self.assertRaises(ValueError):
            validate_report(package, report)


if __name__ == '__main__':
    unittest.main()
