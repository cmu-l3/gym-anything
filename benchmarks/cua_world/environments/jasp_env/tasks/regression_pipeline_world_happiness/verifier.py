#!/usr/bin/env python3
"""Stub verifier for regression_pipeline_world_happiness task.
Actual verification is done externally via VLM evaluators.
"""


def verify_regression_pipeline(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier -- VLM evaluation is external"}
