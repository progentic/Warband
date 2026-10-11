# Odin Style Guide

This project uses a small local style guide so contributors write code that is easy to review.

- Package names use short lowercase nouns.
- Files use `snake_case.odin`.
- Procedures and fields use `snake_case`.
- Public types and distinct identifiers use `PascalCase`.
- State-changing procedures use clear verbs such as `commit_verified_fact`, `issue_capability`, or `bind_approval`.
- Read-only procedures use verbs such as `get`, `find`, `validate`, `verify`, or `derive`.
- Broad packages named `utils`, `helpers`, or `common` should not be created.
- Package-level mutable global state is prohibited unless a later architecture decision explicitly permits it.
- Dependencies should be passed explicitly.
- Security-critical procedures should be short enough to review as one decision path.
- Comments should explain why a rule exists, not repeat what the code already says.
