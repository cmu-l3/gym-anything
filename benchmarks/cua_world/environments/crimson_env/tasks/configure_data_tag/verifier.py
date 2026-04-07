#!/usr/bin/env python3
"""Stub verifier for configure_data_tag task.
Actual verification is done externally via VLM evaluators.
"""


def verify_configure_data_tag(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier - VLM evaluation is external"}
