# Engineering Goals

This document states what the engineering effort is trying to achieve.

## Primary goals

### Verifiable authority

Every authoritative state change must be linked to a proposal, policy decision, execution result, evaluation result, and audit record.

### Default-deny behavior

Malformed, unknown, stale, unauthorized, or unverifiable actions must be rejected.

### Small trusted core

The code that can authorize execution, issue capabilities, accept evidence, or commit state must remain small and easy to review.

### Bounded failure

Retries, execution time, resource use, capability lifetime, and task scope must have explicit limits.

### Provider independence

Changing the language model provider must not change the runtime's authority, policy, state, or audit rules.

### Replayable state

The runtime must be able to rebuild authoritative state from accepted facts in the event history.

### Clear failure

When Warband cannot verify an action, it must stop, explain the reason safely, and avoid pretending the task succeeded.

### Testable documentation

Every architectural guarantee must have a named verification method.
