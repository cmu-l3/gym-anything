#!/usr/bin/env python3
"""Stub verifier for position_robot_arm task.
Actual verification is done externally via VLM evaluators.
"""


def verify_position_robot_arm(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
