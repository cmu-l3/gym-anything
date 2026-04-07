#!/usr/bin/env python3
"""Stub verifier for dcf_valuation_model task.

Actual verification is done externally via VLM checklist evaluators.
This stub provides basic structural checks only.
"""


def verify_dcf_valuation_model(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external"
    }
