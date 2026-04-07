"""
Verifier stub for earthquake_emergency_response task.
Full evaluation is performed by the VLM checklist verifier.
"""
import json
import os
import tempfile


def verify_earthquake_emergency_response(traj, env_info, task_info):
    """
    Stub verifier — returns pass=True so the VLM checklist pipeline runs.
    The real scoring happens via vlm_checklist.json evaluated by
    vlm_checklist_verifier.py.
    """
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — use VLM checklist evaluation for scoring.",
    }
