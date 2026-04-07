#!/usr/bin/env python3
"""
Stub verifier for procure_to_pay_cycle task.
Actual verification is done externally via VLM checklist evaluator.
"""


def verify_procure_to_pay_cycle(traj, env_info, task_info):
    """Stub verifier -- VLM evaluation is external."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier -- VLM evaluation is external"}
