"""Guard the bounded Python E1 dependencies, including deliberate violations."""
import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PURE_IMPORTS = {'governance.py': {'dataclasses', 'enum'}, 'manifest_rules.py': {'dataclasses'}}
PURE_BUILTINS = {'tuple', 'frozenset', 'dict', 'set', 'sum', 'any', 'all', 'sorted', 'type', 'len'}
PURE_LOW = {
    'governance.py': {'matches_typed_member', 'starts_with'},
    'manifest_rules.py': {'includes_markers', 'contains_text', 'target_flags'},
}
RAW_HIGH_CALLS = {'open', 'print', 'exec', 'eval', '__import__', 'getattr', 'Path'}
HIGH = {
    'check_docs.py': {'main'},
    'document_io.py': {'read_inventory'},
    'build_manifest.py': {'main', 'acquire_artifact', 'acquire_build_observation',
                          'acquire_compiler_provenance', 'publish_verified_manifest'},
    'governance.py': {'validate_inventory'},
    'manifest_rules.py': {'construct_manifest'},
}
POLICY_CALLS = {
    'document_io.py': {'assemble_inventory', 'validate_inventory', 'describe_validation'},
    'manifest_io.py': {'construct_manifest', 'validate_platform', 'validate_architecture',
                       'validate_machine', 'describe_compiler', 'assemble_artifact',
                       'assemble_build_observation'},
}


class E1StructureControls(unittest.TestCase):
    def test_effect_and_dependency_boundaries_reject_real_violations(self):
        for name, imports in PURE_IMPORTS.items():
            source = (ROOT / 'scripts' / name).read_text()
            assert_pure_module(source, imports)
            assert_mid_calls_only_low(source, HIGH[name], PURE_LOW[name])
        for name, functions in HIGH.items():
            assert_high_has_no_raw_api((ROOT / 'scripts' / name).read_text(), functions)
        for name, policies in POLICY_CALLS.items():
            assert_low_has_no_policy_call((ROOT / 'scripts' / name).read_text(), HIGH.get(name, set()), policies)
        with self.assertRaisesRegex(ValueError, 'impure call'):
            assert_pure_module('def decision(value):\n    print(value)\n', set())
        with self.assertRaisesRegex(ValueError, 'raw API'):
            assert_high_has_no_raw_api('def main():\n    path.read_text()\n', {'main'})
        with self.assertRaisesRegex(ValueError, 'upward call'):
            assert_low_has_no_policy_call('def reader():\n    validate_inventory(value)\n', set(), {'validate_inventory'})
        with self.assertRaisesRegex(ValueError, 'Mid dependency'):
            assert_mid_calls_only_low('def first():\n    second()\ndef second():\n    return value\n', set(), set())


def assert_pure_module(source, permitted_imports):
    tree = ast.parse(source)
    local_names = {node.name for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef))}
    allowed = local_names | PURE_BUILTINS | {'dataclass', 'frozenset', 'ValueError'}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            raise ValueError('impure module import')
        if isinstance(node, ast.ImportFrom) and node.module not in permitted_imports:
            raise ValueError('impure module import')
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id not in allowed:
                raise ValueError('impure call: ' + node.func.id)
            if isinstance(node.func, ast.Attribute) and node.func.attr != 'startswith':
                raise ValueError('impure call: ' + node.func.attr)


def assert_high_has_no_raw_api(source, functions):
    for function in ast.parse(source).body:
        if isinstance(function, ast.FunctionDef) and function.name in functions:
            if any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                   for node in ast.walk(function)):
                raise ValueError('raw API in High: ' + function.name)
            if any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                   and node.func.id in RAW_HIGH_CALLS for node in ast.walk(function)):
                raise ValueError('raw API in High: ' + function.name)


def assert_low_has_no_policy_call(source, high_functions, policies):
    for function in ast.parse(source).body:
        if isinstance(function, ast.FunctionDef) and function.name not in high_functions:
            for node in ast.walk(function):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in policies:
                    raise ValueError('upward call in Low: ' + function.name)


def assert_mid_calls_only_low(source, high_functions, low_functions):
    functions = {node.name: node for node in ast.parse(source).body if isinstance(node, ast.FunctionDef)}
    for name, function in functions.items():
        if name not in high_functions | low_functions:
            for node in ast.walk(function):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                    if node.func.id in functions and node.func.id not in low_functions:
                        raise ValueError('forbidden Mid dependency: ' + name)


if __name__ == '__main__':
    unittest.main()
