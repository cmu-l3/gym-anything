#!/usr/bin/env python3
"""
Verifier for cancel_provider_schedule task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_schedule(traj, env_info, task_info):
    """
    Verify that all 3 appointments for Dr. Chen were cancelled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metrics
    total_appts = result.get('total_appointments', 0)
    cancelled_count = result.get('cancelled_appointments', 0)
    active_count = result.get('active_appointments', 0)
    
    expected_total = 3
    
    score = 0
    feedback = []

    # Criterion 1: Appointments should still exist (don't delete them!)
    if total_appts >= expected_total:
        score += 10
        feedback.append("Appointments preserved in schedule")
    else:
        feedback.append(f"Appointments missing (found {total_appts}, expected {expected_total})")

    # Criterion 2: All target appointments cancelled
    # We expect exactly 3 cancellations for the 3 test appointments
    if cancelled_count == expected_total:
        score += 90
        feedback.append(f"All {expected_total} appointments successfully cancelled")
    elif cancelled_count > 0:
        partial_score = (cancelled_count / expected_total) * 90
        score += partial_score
        feedback.append(f"Partially cancelled: {cancelled_count}/{expected_total} appointments")
    else:
        feedback.append("No appointments were cancelled")

    # Anti-gaming / Safety check
    # If active appointments remain, it's a fail on completion
    if active_count > 0:
        feedback.append(f"{active_count} appointments still active!")
    
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }