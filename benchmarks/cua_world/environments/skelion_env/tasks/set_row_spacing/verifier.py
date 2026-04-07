#!/usr/bin/env python3
"""Stub verifier for set_row_spacing task.
Actual verification is done externally via VLM evaluators.
"""


def verify_set_row_spacing(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation.

    VLM evaluator checks: Solar panels are placed on the roof with visible
    inter-row gaps of approximately 2 meters. The spacing between panel rows
    should be noticeably larger than the panel width itself.
    """
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
