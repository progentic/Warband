# Verification Baseline

This folder explains how Warband proves that its architecture is still being followed.

The first implementation should focus on invariant and negative-path testing before adding real model providers or powerful tools.

## Core acceptance rule

A model-originated completion claim cannot change task state unless an independent evaluator produces valid evidence and the state-transition boundary accepts the transition.
