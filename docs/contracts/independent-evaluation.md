# Independent Evaluation Contract

## Purpose

Prevent a model from declaring its own work successful.

## User contract

Warband double-checks the result using evidence such as test output, file hashes, exit codes, or approved API responses.

## Engineering contract

Evaluators compare observed results with typed expected effects. Evaluation results must identify the evaluator, evidence source, result, and covered criteria. The Phase 2 [producer and NoOpV1 registry](../decisions/0005-event-integrity-acceptance-and-recovery.md#5-observer-and-evaluator-trust) binds exact observation bytes, digest, producer/version, claim and criterion. Observation, evaluation and state acceptance have separate responsibilities; only the state boundary can accept the result.

## Security contract

The proposal engine must not serve as the sole evaluator of its own action. Model confidence is not evidence. The Phase 2 no-op observer and evaluator are separate modules in one trusted process. This establishes deterministic responsibility separation, not resistance to compromise of that process. Later external execution needs independently reviewed observation and isolation evidence.

## Verification contract

Tests must prove that a completion claim without independent evidence cannot change task state. Unknown producers/versions, changed observation digests, mismatched criteria and cross-attempt references must reject. An indeterminate observation cannot be accepted as returned no-op evidence.

## Failure behavior

If the evaluator cannot prove success, the task remains incomplete. Warband may request approval, request more evidence, or stop. A retry requires recorded proof that it is safe and a new authorized attempt; uncertain work is never automatically redispatched.
