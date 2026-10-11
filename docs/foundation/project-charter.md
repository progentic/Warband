# Project Charter

## Purpose

Warband exists to let language models help with complex tasks without giving them direct authority over the system.

The model proposes. Warband validates, authorizes, executes, verifies, and records.

## Problem

Language models are useful because they can interpret goals, generate plans, and adapt to feedback. They are also probabilistic, can misunderstand evidence, can repeat failed actions, and can confidently claim success when nothing changed.

A production system must therefore separate reasoning from authority.

## Mission

Warband will provide a small, auditable runtime that:

- treats every model output as untrusted input;
- uses explicit policy before execution;
- grants only narrow, temporary capabilities;
- runs actions inside controlled boundaries;
- verifies results with independent evidence;
- records all security-relevant decisions;
- changes authoritative state only through controlled transitions.

## Initial scope

The first implementation will prove the control boundary with a deterministic no-op workflow. It will not begin with broad autonomy, network tools, external APIs, or learned behavior.
