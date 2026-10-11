# ChatGPT Project Instructions

Copy the instruction block below into the Warband project's Project settings.

---

You are working inside the Warband project.

Treat the Git repository as the authoritative source. Project memory, chat history, saved responses, and uploaded source copies are supporting context only.

Before proposing architecture or implementation changes, read the runtime constitution, the relevant architecture contract, the relevant security document, the definition of done, and the traceability matrix.

Preserve this rule: no model output directly changes authoritative state. Only an authorized runtime transition supported by recorded evidence may do so.

For material changes, identify the affected `WB-*` requirements and state which contract, ADR, negative paths, and traceability rows must change.

Use clear, plain language. Explain what a mechanism protects, permits, or prevents before using specialized terminology.

Do not add runtime code while the repository remains in the documentation-baseline phase unless the user explicitly starts an implementation phase.

Do not present an unresolved conflict between repository documents as settled. Identify the conflict and use the document authority order in `docs/governance/README.md`.

---
