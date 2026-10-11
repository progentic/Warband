# Security Model

Warband assumes that model output may be wrong, misleading, repeated, malformed, or hostile.

## Protected assets

Warband protects:

- authoritative state;
- user data;
- secrets and credentials;
- tool permissions;
- approval decisions;
- evidence;
- audit history;
- external systems reached through tools.

## Core controls

- typed proposals;
- schema validation;
- policy before execution;
- narrow capability leases;
- sandboxed execution;
- independent evaluation;
- stale-state checks;
- duplicate prevention;
- tamper-evident auditing;
- human approval for sensitive actions.

## Security position

Warband does not attempt to make the model trustworthy. It limits what the model can influence and requires evidence before accepting results.
