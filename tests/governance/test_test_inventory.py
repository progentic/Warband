"""Controls prove that omission and falsely green reports fail verification."""
from pathlib import Path
import sys
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
