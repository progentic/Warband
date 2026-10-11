# Glossary

## Authoritative state

The runtime's accepted view of what is true now. Only verified, policy-authorized facts may change it.

## Audit projection

A view of the event history that includes proposals, decisions, failures, approvals, observations, and transitions.

## Capability

A narrow, temporary permission that allows one approved action against a defined target.

## Evaluator

A component that checks observed results against explicit success criteria.

## Evidence

Recorded, machine-checkable support for an evaluator result.

## Event

A record that something happened.

## Fact

A verified condition accepted by the runtime.

## Proposal

An untrusted, typed suggestion from a model or another external source.

## Proposal engine

A language model used to interpret intent and generate candidate actions.

## Recovery policy

The predefined response if an action fails or causes an unwanted effect. It may restore, compensate, require approval, or reject execution.

## State projection

A limited, read-only view of runtime information prepared for a specific reader, such as the model or user.

## Trusted core

The smallest set of code allowed to authorize execution, issue capabilities, verify evidence, bind approvals, or commit state.
