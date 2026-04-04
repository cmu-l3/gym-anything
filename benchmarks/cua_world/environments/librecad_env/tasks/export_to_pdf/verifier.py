#!/usr/bin/env python3
"""Stub verifier for export_to_pdf task.
Actual verification is done externally via VLM evaluation.
"""

def verify_export_to_pdf(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
