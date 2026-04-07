#!/usr/bin/env python3
"""Stub verifier for qa_review_implant_plan task.
Actual verification is done externally via VLM checklist evaluators.
"""


def verify_qa_review_implant_plan(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
