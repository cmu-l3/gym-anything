#!/usr/bin/env python3
"""Stub verifier for insert_panels_portrait task.
Actual verification is done externally via VLM evaluators.
"""


def verify_insert_panels_portrait(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation.

    VLM evaluator checks: Solar panels are placed on the roof in portrait
    orientation — each panel appears taller than it is wide (long edge vertical).
    """
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
