#!/usr/bin/env python3
"""Stub verifier for debug_hr_analytics_pipeline task.
Actual verification is done externally via VLM evaluators.
"""


def verify_hr_analytics(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier - VLM evaluation is external",
    }
