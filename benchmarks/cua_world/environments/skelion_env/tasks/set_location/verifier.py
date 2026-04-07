#!/usr/bin/env python3
"""Stub verifier for set_location task.
Actual verification is done externally via VLM evaluators.
"""


def verify_set_location(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation.

    VLM evaluator checks: The Model Info dialog (or geo-location confirmation)
    shows San Francisco, CA as the location with latitude approximately 37.77°N
    and longitude approximately -122.42°W.
    """
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
