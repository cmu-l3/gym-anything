#!/usr/bin/env python3
"""Stub verifier for pass_quality_check task.
Actual verification is done externally via VLM evaluation.
"""


def verify_pass_quality_check(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
