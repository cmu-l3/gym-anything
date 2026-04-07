"""
Verifier stub for expense_fraud_investigation.
VLM checklist verification is used externally for scoring.
"""

from typing import Any, Dict


def verify_task(traj: dict, env_info: dict, task_info: dict) -> Dict[str, Any]:
    """Stub verifier — VLM evaluation is done externally."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM checklist evaluation is external.",
    }
