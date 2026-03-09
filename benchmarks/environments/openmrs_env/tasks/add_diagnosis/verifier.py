#!/usr/bin/env python3
"""Stub verifier for add_diagnosis task.
Actual verification is done externally via VLM evaluation.
"""


def verify_add_diagnosis(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
