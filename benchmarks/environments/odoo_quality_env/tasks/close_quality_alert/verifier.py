#!/usr/bin/env python3
"""Stub verifier for close_quality_alert task.
Actual verification is done externally via VLM evaluation.
"""


def verify_close_quality_alert(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
