# Independent Evaluation Contract

## Purpose

Prevent a model from declaring its own work successful.

## User contract

Warband double-checks the result using evidence such as test output, file hashes, exit codes, or approved API responses.

## Engineering contract

Evaluators compare observed results with typed expected effects. Evaluation results must identify the evaluator, evidence source, result, and covered criteria.

## Security contract

The proposal engine must not serve as the sole evaluator of its own action. Model confidence is not evidence.

## Verification contract

Tests must prove that a completion claim without independent evidence cannot change task state.

## Failure behavior

If the evaluator cannot prove success, the task remains incomplete. Warband may retry, request approval, request more evidence, or stop.
