# Architecture Overview

Warband is a policy-controlled execution runtime built around a simple separation of responsibility.

The language model interprets a task and proposes an action. The runtime decides whether that action is allowed. A controlled executor performs the action. Independent evaluators check the result. Only then may the state machine record a verified change.

## Main layers

1. Interaction: accepts user intent and displays results.
2. Coordination: manages task flow, retries, and escalation.
3. Authority: applies policy, approval, capabilities, and state-transition rules.
4. Execution: runs tools inside controlled boundaries.
5. Verification: checks evidence and expected effects.
6. Infrastructure: provides storage, model adapters, cryptography, and telemetry.

## Core boundary

Data may flow from the model into the runtime. Authority never flows from the model into the runtime.
