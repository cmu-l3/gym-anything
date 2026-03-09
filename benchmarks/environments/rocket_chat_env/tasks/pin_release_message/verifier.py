#!/usr/bin/env python3
"""Stub verifier for pin_release_message.

Actual verification is handled externally via VLM evaluators.
"""


def verify_pin_release_message(traj, env_info, task_info):
    """Stub verifier -- real verification is done externally."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
