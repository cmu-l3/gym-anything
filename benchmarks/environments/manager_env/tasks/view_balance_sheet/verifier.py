#!/usr/bin/env python3
"""Stub verifier for view_balance_sheet task.
Actual verification is done externally via VLM evaluators.
"""


def verify_view_balance_sheet(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
