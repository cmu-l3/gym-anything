"""Adapters that expose gym-anything environments to external training stacks.

Each protocol gets one module (e.g. `verifiers` for Prime Intellect's
verifiers/prime-rl stack). Modules import their third-party dependencies at
import time, so import the specific module you need rather than this package
exporting everything eagerly.
"""
