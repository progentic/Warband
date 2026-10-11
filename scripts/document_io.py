"""Read and parse repository documents into the validation inventory."""
import json
import re
from pathlib import Path

from governance import Document, Inventory, Link

LINK_PATTERN = re.compile(r'(?<!!)\[[^\]]+\]\(([^)]+)\)')
IDENTIFIER_PATTERN = re.compile(r'\bWB-CON-\d{3}\b')
FRONTMATTER_PATTERN = re.compile(
    r'\A---\s*\n(?=.*^name:\s*\S)(?=.*^description:\s*.+)^.*?\n---\s*\n',
    re.MULTILINE | re.DOTALL,
)
IGNORED_DIRECTORIES = frozenset(('.git', '.local', 'out', 'build', 'warband-docs-bootstrap-v2'))
EXTERNAL_PREFIXES = ('http://', 'https://', 'mailto:', '#')


def read_inventory(root: Path) -> Inventory:
    paths = tuple(walk_files(root))
    readable = tuple(path for path in paths if not path.is_symlink())
    documents = tuple(read_document(root, path) for path in readable if path.suffix == '.md')
    links = tuple(link for path in readable if path.suffix == '.md' for link in read_links(root, path))
    return Inventory(
        frozenset(str(path.relative_to(root)) for path in paths),
        frozenset(path.name for path in root.iterdir()), documents, links,
        read_phase(root / 'project.json'),
        tuple(str(path.relative_to(root)) for path in paths if path.name == 'AGENTS.override.md'),
        tuple(str(path.relative_to(root)) for path in paths if path.is_symlink()),
    )


def walk_files(directory: Path, root: Path | None = None):
    root = root or directory
    for path in sorted(directory.iterdir()):
        if directory == root and path.name in IGNORED_DIRECTORIES:
            continue
        if path.is_symlink():
            yield path
        elif path.is_dir():
            yield from walk_files(path, root)
        elif path.is_file():
            yield path


def read_document(root: Path, path: Path) -> Document:
    text = path.read_text(encoding='utf-8')
    return Document(str(path.relative_to(root)), frozenset(text.splitlines()),
                    frozenset(IDENTIFIER_PATTERN.findall(text)), path.stat().st_size,
                    bool(FRONTMATTER_PATTERN.search(text)))


def read_links(root: Path, path: Path) -> tuple[Link, ...]:
    targets = LINK_PATTERN.findall(path.read_text(encoding='utf-8'))
    return tuple(resolve_link(root, path, target.strip()) for target in targets
                 if target.strip() and not target.strip().startswith(EXTERNAL_PREFIXES))


def resolve_link(root: Path, path: Path, target: str) -> Link:
    resolved = (path.parent / target.split('#', 1)[0]).resolve()
    return Link(str(path.relative_to(root)), target,
                resolved.is_relative_to(root.resolve()), resolved.exists())


def read_phase(path: Path):
    if not path.is_file() or path.is_symlink():
        return None
    try:
        value = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)
    except (ValueError, UnicodeError):
        return None
    if type(value) is not dict or set(value) != {'phase'}:
        return None
    return value['phase']


def unique_object(pairs):
    value = dict(pairs)
    if len(value) != len(pairs):
        raise ValueError('duplicate JSON key')
    return value


def report_findings(findings) -> int:
    for finding in findings:
        subject = ': '.join(filter(None, (finding.subject, finding.detail)))
        print(f'ERROR: {finding.code}: {subject}')
    if findings:
        return 1
    print('Warband documentation governance checks passed.')
    return 0
