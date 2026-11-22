# User guide

This guide explains the current Warband program in plain language.

## Show the version

If you have a built copy, run `warband version`.

It prints `Warband Phase 1 foundation (no execution authority)`. The program cannot carry out AI tasks yet.

## Print the test sample

Run `warband fixture`.

It prints the same test bytes as a line of hexadecimal text. You can compare the line from two computers to check that they produce the same sample.

## Fix an unrecognized command

Warband accepts only `version` and `fixture`. A missing command, an unknown command, or extra words produce `usage: warband version | fixture`.

The program rejects the command instead of guessing. Use one of the two commands above.

## Planned features

Warband's design calls for checks before actions, limited access, approval requests, result checks, and an activity history.

The current program does not offer these features or an AI task screen.
