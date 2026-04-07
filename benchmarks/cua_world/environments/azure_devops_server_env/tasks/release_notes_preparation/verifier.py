#!/usr/bin/env python3
"""Stub verifier for release_notes_preparation task.
Actual verification is done externally via VLM evaluators.
"""


def verify_release_notes_preparation(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
