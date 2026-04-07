#!/usr/bin/env python3
"""Stub verifier for insert_panels_tilted task.
Actual verification is done externally via VLM evaluators.
"""


def verify_insert_panels_tilted(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation.

    VLM evaluator checks: Solar panels are placed on the roof with a visible
    30-degree tilt (panels are angled, not flat against the roof surface).
    The Skelion dialog should have shown tilt=30 before insertion.
    """
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
