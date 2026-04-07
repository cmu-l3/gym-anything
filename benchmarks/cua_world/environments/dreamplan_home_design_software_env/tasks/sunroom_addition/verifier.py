#!/usr/bin/env python3
"""Stub verifier for sunroom_addition task.
Actual verification is done externally via VLM evaluators (vlm_checklist_verifier).
"""


def verify_sunroom_addition(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier -- VLM evaluation is external"}
