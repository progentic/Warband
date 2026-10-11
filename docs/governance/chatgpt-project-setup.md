# ChatGPT Project Setup

This guide explains how to configure a ChatGPT Project for Warband without confusing project context with repository authority.

## Create the project

1. Create a dedicated ChatGPT Project named `Warband`.
2. Select project-only memory when that option is available. This keeps Warband context separate from unrelated conversations.
3. Add the text from `chatgpt-project-instructions.md` to Project settings.
4. Add the files listed in `project-source-manifest.md` as project sources.
5. Keep architecture and implementation chats inside this project.

## Sharing

Grant edit access only to people allowed to change project instructions and sources. Use chat access for reviewers who need to discuss the project but should not manage its configuration.

## Source control rule

Project sources are convenience copies. Record the repository commit used for the upload in `project-source-manifest.md`.

When a source changes in Git:

1. update the repository first;
2. review and commit the change;
3. replace the project source;
4. update the synchronization record.

## Decision rule

A chat response, saved project response, or project memory item is not an accepted architecture decision. Convert material decisions into an ADR and commit it to `docs/decisions/`.
