# Package Boundaries

Each package must have one clear owner and one clear reason to exist.

## `domain`

Defines identifiers and immutable vocabulary. It does not authorize, execute, store, or mutate.

## `runtime`

Coordinates work. It does not bypass policy, evaluation, capability, or state-transition rules.

## `policy`

Returns explicit policy decisions. It does not run tools or commit state.

## `capability`

Issues, verifies, expires, and revokes narrow execution rights.

## `execution`

Runs approved actions within resource and time limits.

## `evaluation`

Turns observations into evaluation results. It does not claim authority over state.

## `state`

Owns authoritative state and valid transitions.

## `audit`

Records and verifies tamper-evident history.

## `model`

Adapts model providers into the proposal interface. It remains outside the trusted authority core.

## `tools`

Implements bounded actions. Tools may not call each other unless a documented execution plan permits it.

## Implemented Phase 1 packages

`cmd/warband` owns command routing and presentation. `src/domain` owns distinct identifiers, typed errors, and pure fixture validation. `src/fixture` owns fixed-width byte encoding/decoding through the Odin endian library. It does not authorize or accept facts. `tests/odin-packages.json` enumerates the foundation tests.

`gateway` and `recovery` remain planned boundaries referenced by traceability. Neither is implemented in Phase 1; their contracts and ownership need follow-on decisions before execution begins. All other runtime packages listed above remain planned.
