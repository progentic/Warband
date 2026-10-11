"""Pure completeness checks for declared packages and compiler JSON reports."""
from dataclasses import dataclass


@dataclass(frozen=True)
class TestPackage:
    path: str
    names: tuple[str, ...]


def validate_packages(declared: tuple[TestPackage, ...], discovered: tuple[TestPackage, ...]):
    if not declared:
        raise ValueError('test manifest is empty')
    expected = {package.path: package.names for package in declared}
    actual = {package.path: package.names for package in discovered}
    if len(expected) != len(declared):
        raise ValueError('duplicate package in manifest')
    if expected != actual:
        raise ValueError('manifest differs from discovered test package/name inventory')
    if any(not package.names for package in declared):
        raise ValueError('empty test package')


def validate_report(package: TestPackage, report: dict):
    tests = tuple(test for values in report['packages'].values() for test in values)
    names = tuple(sorted(test['name'] for test in tests))
    if names != package.names:
        raise ValueError('compiler report test names differ from manifest')
    if report['total'] != len(package.names):
        raise ValueError('compiler report total differs from expected test count')
    if report['success'] != report['total']:
        raise ValueError('compiler report contains failed or skipped tests')
    if any(test['success'] is not True for test in tests):
        raise ValueError('compiler report contains unsuccessful test')
