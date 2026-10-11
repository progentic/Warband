# Testing Standard

Warband tests must prove both correct behavior and safe failure.

## Required test types

### Unit tests

Check one function or package rule in isolation.

### Integration tests

Check that multiple packages enforce the full pipeline.

### Invariant tests

Prove constitutional rules such as no direct state mutation and no unverified completion.

### Negative-path tests

Actively try malformed, stale, duplicate, unauthorized, expired, tampered, or misleading inputs.

### Replay tests

Rebuild state from recorded facts and verify the same result.

## Rule

A happy-path test is not enough for a security boundary. Every permission or state transition must have at least one rejection test.
