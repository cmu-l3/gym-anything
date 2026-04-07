#!/usr/bin/env python3
"""Stub verifier for insert_solar_panels task.
Actual verification is done externally via VLM evaluators.
"""


def verify_insert_solar_panels(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation.

    VLM evaluator checks: Solar panels are visibly placed on the flat roof
    of the building in SketchUp. The roof surface should be covered by a grid
    of blue/dark rectangular panel shapes arranged in rows.
    """
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
