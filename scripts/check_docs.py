#!/usr/bin/env python3
"""Validate the explicit project phase and unchanged governance obligations."""
import sys
from pathlib import Path

from document_io import read_inventory, report_findings
from governance import validate_inventory

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    inventory = read_inventory(ROOT)
    findings = validate_inventory(inventory)
    return report_findings(findings)


if __name__ == '__main__':
    sys.exit(main())
