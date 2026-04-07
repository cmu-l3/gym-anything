"""
Verifier for pharmacovigilance_alert_response task.
Stub verifier — actual evaluation is performed by the VLM checklist verifier.
"""
import json
import os
import tempfile


def verify_pharmacovigilance_alert_response(traj, env_info, task_info):
    """Stub verifier — VLM checklist evaluation is external."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — actual evaluation performed by VLM checklist verifier."
    }
