#!/usr/bin/env python3
"""Stub verifier for toggle_lobby task.
Actual verification is handled externally via VLM evaluators.
"""


def verify_toggle_lobby(traj, env_info, task_info):
    """Stub verifier -- real verification is done externally."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
