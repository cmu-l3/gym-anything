"""Adapters that expose gym-anything environments to external stacks.

Each provider gets one subpackage:

* ``prime_rl`` — Prime Intellect's verifiers/prime-rl stack and the
  Environments Hub loader.
* ``harbor`` — the Harbor evaluation framework (environment backend, task
  compiler, in-container runtime, and agent).

Subpackages import their third-party dependencies at import time, so import
the specific module you need rather than this package exporting everything
eagerly.
"""
