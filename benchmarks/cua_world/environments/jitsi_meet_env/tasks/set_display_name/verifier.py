#!/usr/bin/env python3
"""Stub verifier for set_display_name task.
Actual verification is handled externally via VLM evaluators.
"""


def verify_set_display_name(traj, env_info, task_info):
    """Stub verifier -- real verification is done externally."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
