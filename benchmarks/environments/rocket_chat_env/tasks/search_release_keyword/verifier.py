#!/usr/bin/env python3
"""Stub verifier for search_release_keyword.

Actual verification is handled externally via VLM evaluators.
"""


def verify_search_release_keyword(traj, env_info, task_info):
    """Stub verifier -- real verification is done externally."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
