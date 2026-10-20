"""Pure documentation rules; no filesystem or process access."""
from dataclasses import dataclass
from enum import StrEnum

PHASE_DECLARATION = 'project.json'
ROOT_GUIDANCE = 'AGENTS.md'
DOC_GUIDANCE = 'docs/AGENTS.md'
REQUIRED_FILES = (
    'AGENTS.md', 'README.md', 'docs/AGENTS.md', 'docs/README.md',
    'docs/foundation/runtime-constitution.md', 'docs/governance/README.md',
    'docs/governance/chatgpt-project-setup.md',
    'docs/governance/chatgpt-project-instructions.md',
    'docs/governance/project-source-manifest.md', 'docs/governance/agent-guidance.md',
    'docs/verification/traceability-matrix.md',
    '.agents/skills/warband-governance-review/SKILL.md', PHASE_DECLARATION,
    'docs/contracts/authoritative-state.md', 'docs/contracts/model-proposals.md',
    'docs/contracts/independent-evaluation.md', 'docs/contracts/event-integrity.md',
    'docs/verification/constitutional-invariants.md',
    'docs/verification/negative-path-catalog.md',
    'docs/decisions/0001-models-are-untrusted-proposal-engines.md',
    'docs/decisions/0002-event-sourced-authoritative-state.md',
    'docs/decisions/0003-single-event-store-dual-projections.md',
)
CONTRACT_HEADINGS = (
    '## User contract', '## Engineering contract',
    '## Security contract', '## Verification contract',
)
RUNTIME_DIRECTORIES = frozenset(('src', 'cmd'))
DOCUMENTATION_PHASE = 0
FOUNDATION_PHASE = 1
AUTHORITY_PHASE = 2
ALLOWED_PHASES = (DOCUMENTATION_PHASE, FOUNDATION_PHASE, AUTHORITY_PHASE)
PHASE_TWO_ADR = 'docs/decisions/0005-event-integrity-acceptance-and-recovery.md'
PHASE_TWO_RECORDS = (
    PHASE_TWO_ADR, 'docs/governance/PHASE_PLAN.md',
    'docs/engineering/phase2-entry-review.md',
    'docs/engineering/coding-standard.md',
    'docs/architecture/dependency-rules.md', 'docs/security/threat-model.md',
    'docs/security/trust-model.md',
)
ACCEPTED_DECISION_LINE = '- **Status:** Accepted'
DECISION_STATUS_PREFIX = '- **Status:** '
GUIDANCE_FILES = (ROOT_GUIDANCE, DOC_GUIDANCE)
CONTRACT_ROOT = 'docs/contracts/'
CONTRACT_INDEX = 'docs/contracts/README.md'
GUIDANCE_LIMIT = 32 * 1024
SKILL_PATH = '.agents/skills/warband-governance-review/SKILL.md'
CONSTITUTION_PATH = 'docs/foundation/runtime-constitution.md'
MATRIX_PATH = 'docs/verification/traceability-matrix.md'
SUCCESS_STATUS = 0
FAILURE_STATUS = 1
SUCCESS_MESSAGE = 'Warband documentation governance checks passed.'
EMPTY_MESSAGE = ''


class FindingCode(StrEnum):
    MISSING_REQUIRED = 'missing_required_file'
    INVALID_PHASE = 'invalid_phase'
    UNACCEPTED_DECISION = 'unaccepted_phase_decision'
    PREMATURE_RUNTIME = 'premature_runtime'
    OVERRIDE = 'unexpected_override'
    GUIDANCE_SIZE = 'guidance_size_limit'
    SKILL_METADATA = 'invalid_skill_frontmatter'
    CONTRACT_HEADING = 'missing_contract_heading'
    LINK_ESCAPE = 'link_escapes_repository'
    BROKEN_LINK = 'broken_link'
    UNMAPPED_ID = 'unmapped_constitution_id'
    UNDEFINED_ID = 'undefined_constitution_id'
    SYMLINK = 'symlinked_input'


@dataclass(frozen=True)
class Finding:
    code: FindingCode
    subject: str
    detail: str = ''


@dataclass(frozen=True)
class Document:
    path: str
    headings: frozenset[str]
    identifiers: frozenset[str]
    byte_count: int
    skill_frontmatter: bool


@dataclass(frozen=True)
class Link:
    source: str
    target: str
    inside: bool
    exists: bool


@dataclass(frozen=True)
class Inventory:
    files: frozenset[str]
    directories: frozenset[str]
    documents: tuple[Document, ...]
    links: tuple[Link, ...]
    phase: object
    overrides: tuple[str, ...]
    symlinks: tuple[str, ...]


@dataclass(frozen=True)
class FileCatalog:
    files: frozenset[str]
    directories: frozenset[str]
    overrides: tuple[str, ...]
    symlinks: tuple[str, ...]


@dataclass(frozen=True)
class DocumentationResult:
    findings: tuple[Finding, ...]
    message: str
    status: int


def validate_inventory(inventory: Inventory) -> tuple[Finding, ...]:
    return (required_findings(inventory) + phase_findings(inventory)
            + guidance_findings(inventory) + contract_findings(inventory)
            + link_findings(inventory) + traceability_findings(inventory)
            + symlink_findings(inventory) + phase_two_record_findings(inventory))


def assemble_inventory(catalog: FileCatalog, documents, links, phase) -> Inventory:
    return Inventory(catalog.files, catalog.directories, documents, links, phase,
                     catalog.overrides, catalog.symlinks)


def describe_validation(findings: tuple[Finding, ...]) -> DocumentationResult:
    if findings:
        return DocumentationResult(findings, EMPTY_MESSAGE, FAILURE_STATUS)
    return DocumentationResult(findings, SUCCESS_MESSAGE, SUCCESS_STATUS)


def required_findings(inventory: Inventory) -> tuple[Finding, ...]:
    return tuple(Finding(FindingCode.MISSING_REQUIRED, path)
                 for path in REQUIRED_FILES if path not in inventory.files)


def phase_findings(inventory: Inventory) -> tuple[Finding, ...]:
    if not matches_typed_member(inventory.phase, int, ALLOWED_PHASES):
        return (Finding(FindingCode.INVALID_PHASE, PHASE_DECLARATION),)
    if inventory.phase == DOCUMENTATION_PHASE:
        return tuple(Finding(FindingCode.PREMATURE_RUNTIME, path)
                     for path in RUNTIME_DIRECTORIES & inventory.directories)
    return ()


def phase_two_record_findings(inventory: Inventory) -> tuple[Finding, ...]:
    if inventory.phase != AUTHORITY_PHASE:
        return ()
    missing = tuple(Finding(FindingCode.MISSING_REQUIRED, path)
                    for path in PHASE_TWO_RECORDS if path not in inventory.files)
    decisions = tuple(d for d in inventory.documents if d.path == PHASE_TWO_ADR)
    unaccepted = tuple(Finding(FindingCode.UNACCEPTED_DECISION, d.path)
                       for d in decisions if prefixed_lines(d.headings, DECISION_STATUS_PREFIX)
                       != (ACCEPTED_DECISION_LINE,))
    return missing + unaccepted


def guidance_findings(inventory: Inventory) -> tuple[Finding, ...]:
    findings = tuple(Finding(FindingCode.OVERRIDE, path) for path in inventory.overrides)
    guidance = tuple(d for d in inventory.documents if d.path in GUIDANCE_FILES)
    if sum(d.byte_count for d in guidance) > GUIDANCE_LIMIT:
        findings += (Finding(FindingCode.GUIDANCE_SIZE, ROOT_GUIDANCE, DOC_GUIDANCE),)
    skills = tuple(d for d in inventory.documents if d.path == SKILL_PATH)
    if any(not d.skill_frontmatter for d in skills):
        findings += (Finding(FindingCode.SKILL_METADATA, SKILL_PATH),)
    return findings


def contract_findings(inventory: Inventory) -> tuple[Finding, ...]:
    contracts = tuple(d for d in inventory.documents if starts_with(d.path, CONTRACT_ROOT))
    return tuple(Finding(FindingCode.CONTRACT_HEADING, d.path, heading)
                 for d in contracts if d.path != CONTRACT_INDEX for heading in CONTRACT_HEADINGS
                 if heading not in d.headings)


def link_findings(inventory: Inventory) -> tuple[Finding, ...]:
    escapes = tuple(Finding(FindingCode.LINK_ESCAPE, link.source, link.target)
                    for link in inventory.links if not link.inside)
    missing = tuple(Finding(FindingCode.BROKEN_LINK, link.source, link.target)
                    for link in inventory.links if link.inside and not link.exists)
    return escapes + missing


def traceability_findings(inventory: Inventory) -> tuple[Finding, ...]:
    documents = {document.path: document for document in inventory.documents}
    if CONSTITUTION_PATH not in documents or MATRIX_PATH not in documents:
        return ()  # Required-file findings already explain these absences.
    expected = documents[CONSTITUTION_PATH].identifiers
    actual = documents[MATRIX_PATH].identifiers
    missing = tuple(Finding(FindingCode.UNMAPPED_ID, value) for value in sorted(expected - actual))
    extra = tuple(Finding(FindingCode.UNDEFINED_ID, value) for value in sorted(actual - expected))
    return missing + extra


def symlink_findings(inventory: Inventory) -> tuple[Finding, ...]:
    return tuple(Finding(FindingCode.SYMLINK, path) for path in inventory.symlinks)


def matches_typed_member(value, expected_type, members) -> bool:
    return type(value) is expected_type and value in members


def prefixed_lines(lines, prefix) -> tuple[str, ...]:
    return tuple(line for line in lines if line.startswith(prefix))


def starts_with(text: str, prefix: str) -> bool:
    return text.startswith(prefix)
