# Trust Model

## Untrusted

Warband treats the following as untrusted input:

- model output;
- user-supplied task content;
- tool arguments;
- external API responses;
- raw tool output;
- model confidence;
- model claims of success.

## Conditionally trusted

The following are trusted only after validation:

- normalized proposals;
- policy decisions;
- capability tokens;
- evaluator results;
- approval grants;
- event-store records.

## Trusted core

The trusted core includes the smallest code needed to:

- validate policy;
- issue and verify capabilities;
- bind approvals;
- verify evidence;
- commit state transitions;
- calculate and verify audit hashes.

A failure inside the trusted core may invalidate the system's guarantees. Its size and dependencies must remain limited.

## Phase 2 custody and evidence candidate

[ADR-0005](../decisions/0005-event-integrity-acceptance-and-recovery.md#owner-selected-storage-and-custody-direction) selects a separate custodian OS identity inside the same VM. The runtime owns SQLite; the custodian owns checkpoint metadata and authenticates runtime versus operator operations separately. The VM kernel/root/administrator are trusted. The filesystem, VFS and VM flush configuration are part of the future durability evidence identity.

The registered no-op observer and evaluator are inside the same runtime process but cannot independently accept state. Their role identities and digests prove binding under the trusted-process assumption; they do not prove honesty after process compromise. Unverified SQLite tails, arbitrary producer IDs and a missing custody enrollment remain untrusted. No runtime implementation or protection is claimed by this candidate.
