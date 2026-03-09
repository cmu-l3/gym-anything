#!/usr/bin/env python3
"""Stub verifier for record_medication task.
Actual verification is done externally via VLM evaluation.
"""


def verify_record_medication(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
