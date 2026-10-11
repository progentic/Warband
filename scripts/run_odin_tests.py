#!/usr/bin/env python3
"""Execute explicit packages and verify the pinned compiler's JSON reports."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from test_inventory import TestPackage, validate_packages, validate_report

ROOT = Path(__file__).resolve().parents[1]
TEST_PATTERN = re.compile(r'@\(test\)\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*::\s*proc\s*\(')


def main():
    args = arguments()
    packages = read_manifest(args.manifest)
    validate_packages(packages, discover_packages(ROOT / 'tests/odin'))
    for package in packages:
        execute_package(args.odin, args.output, package)
    print(f'Verified {len(packages)} packages and {sum(len(p.names) for p in packages)} tests.')


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--odin', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'tests/odin-packages.json')
    return parser.parse_args()


def read_manifest(path: Path):
    value = json.loads(path.read_text())
    if type(value.get('phase')) is not int or value['phase'] != 1:
        raise ValueError('test manifest must declare Phase 1')
    return tuple(TestPackage(p['path'], tuple(sorted(p['tests']))) for p in value['packages'])


def discover_packages(directory: Path):
    paths = sorted({path.parent for path in directory.rglob('*.odin')})
    return tuple(TestPackage(str(path.relative_to(ROOT)), discover_names(path)) for path in paths)


def discover_names(directory: Path):
    text = '\n'.join(path.read_text() for path in sorted(directory.glob('*.odin')))
    names = TEST_PATTERN.findall(text)
    if text.count('@(test)') != len(names):
        raise ValueError('unsupported test declaration: ' + str(directory))
    if len(set(names)) != len(names):
        raise ValueError('duplicate test procedure: ' + str(directory))
    return tuple(sorted(names))


def execute_package(odin: Path, output: Path, package: TestPackage):
    output.mkdir(parents=True, exist_ok=True)
    name = Path(package.path).name
    report = output.resolve() / (name + '.json')
    report.unlink(missing_ok=True)
    command = [str(odin.resolve()), 'test', package.path, '-vet', '-warnings-as-errors',
               '-out:' + str(output.resolve() / name), '-define:ODIN_TEST_FANCY=false',
               '-define:ODIN_TEST_RANDOM_SEED=1', '-define:ODIN_TEST_JSON_REPORT=' + str(report)]
    subprocess.run(command, cwd=ROOT, env=execution_environment(odin), check=True)
    validate_report(package, json.loads(report.read_text()))
    print(f'{package.path}: {len(package.names)} named tests verified.')


def execution_environment(odin: Path):
    environment = dict(os.environ)
    bindir = subprocess.check_output([environment['LLVM_CONFIG'], '--bindir'], text=True).strip()
    source = str(odin.resolve().parent)
    environment['PATH'] = os.pathsep.join((source, bindir, environment['PATH']))
    environment['ODIN_ROOT'] = source
    return environment


if __name__ == '__main__':
    main()
