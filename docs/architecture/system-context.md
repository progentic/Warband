# System Context

This document explains what Warband connects and what each external party is allowed to do.

## User

The user provides intent, reviews sensitive actions, and may approve or reject actions that policy marks as requiring human judgment.

The user does not directly edit authoritative runtime state.

## Proposal engine

The language model receives a limited, read-only view of the task and returns a typed proposal.

The proposal engine cannot execute tools, issue capabilities, approve actions, or commit state.

## Tool environment

Tools perform bounded operations such as reading a file, writing a sandbox file, or calling an approved external service.

Tools execute only through the gateway.

## Evaluator

The evaluator checks observed results against explicit success criteria.

The evaluator may produce evidence. It does not directly commit state.

## Event store

The event store records what was proposed, decided, executed, observed, and verified.

The authoritative state is derived from accepted facts in that history.
