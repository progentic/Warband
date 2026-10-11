# Documentation Standard

Warband uses different language for different readers while preserving the same meaning.

## User documentation

Explain what Warband does, what it checks, what requires approval, what failed, and what did not happen.

Use plain language. Explain the protection before naming the mechanism.

## Developer documentation

Name the packages, types, interfaces, control flow, failure rules, and prohibited shortcuts.

## Maintainer documentation

Explain what may change, what requires an architecture decision, what requires migration, and which tests prove the guarantee.

## Security documentation

State the assets, actors, trust boundaries, threats, controls, assumptions, and remaining risks.

Distinguish between:

- guaranteed;
- enforced;
- detected;
- logged;
- assumed;
- unsupported.

## Alignment rule

User, engineering, security, and verification descriptions must not contradict each other.
