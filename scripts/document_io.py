"""Read and parse repository documents into the validation inventory."""
import json
import re
import sys
from pathlib import Path

from governance import Document, DocumentationResult, FileCatalog, Inventory, Link, assemble_inventory

LINK_PATTERN = re.compile(r'(?<!!)\[[^\]]+\]\(([^)]+)\)')
IDENTIFIER_PATTERN = re.compile(r'\bWB-CON-\d{3}\b')
FRONTMATTER_PATTERN = re.compile(
    r'\A---\s*\n(?=.*^name:\s*\S)(?=.*^description:\s*.+)^.*?\n---\s*\n',
    re.MULTILINE | re.DOTALL,
)
IGNORED_DIRECTORIES = frozenset(('.git', '.local', 'out', 'build', 'warband-docs-bootstrap-v2'))
EXTERNAL_PREFIXES = ('http://', 'https://', 'mailto:', '#')
PHASE_FILE = 'project.json'
OVERRIDE_FILE = 'AGENTS.override.md'


def read_inventory(root: Path) -> Inventory:
    paths = collect_paths(root)
    catalog = inspect_catalog(root, paths)
    markdown = readable_markdown(paths)
    documents = read_documents(root, markdown)
    links = read_document_links(root, markdown)
    phase = read_phase(child_path(root, PHASE_FILE))
    return assemble_inventory(catalog, documents, links, phase)


def collect_paths(root: Path):
    return tuple(walk_files(root))


def inspect_catalog(root: Path, paths) -> FileCatalog:
    return FileCatalog(
        frozenset(str(path.relative_to(root)) for path in paths),
        frozenset(path.name for path in root.iterdir()),
        tuple(str(path.relative_to(root)) for path in paths if path.name == OVERRIDE_FILE),
        tuple(str(path.relative_to(root)) for path in paths if path.is_symlink()),
    )


def readable_markdown(paths):
    return tuple(path for path in paths if not path.is_symlink() and path.suffix == '.md')


def read_documents(root: Path, paths):
    return tuple(read_document(root, path) for path in paths)


def read_document_links(root: Path, paths):
    return tuple(link for path in paths for link in read_links(root, path))


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


def report_findings(result: DocumentationResult) -> None:
    for finding in result.findings:
        write_line(format_finding(finding))
    write_optional_line(result.message)


def format_finding(finding) -> str:
    subject = ': '.join(filter(None, (finding.subject, finding.detail)))
    return f'ERROR: {finding.code}: {subject}'


def write_optional_line(text: str) -> None:
    if text:
        write_line(text)


def write_line(text: str) -> None:
    print(text)


def child_path(root: Path, name: str) -> Path:
    return root / name


def project_root(script: str) -> Path:
    return Path(script).resolve().parents[1]


def exit_with_status(status: int) -> None:
    sys.exit(status)
