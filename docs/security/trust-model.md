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
