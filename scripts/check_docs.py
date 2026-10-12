#!/usr/bin/env python3
"""Validate the explicit project phase and unchanged governance obligations."""
from document_io import project_root, read_inventory, report_findings, exit_with_status
from governance import describe_validation, validate_inventory


def main() -> None:
    root = project_root(__file__)
    inventory = read_inventory(root)
    findings = validate_inventory(inventory)
    result = describe_validation(findings)
    report_findings(result)
    exit_with_status(result.status)


if __name__ == '__main__':
    main()
