#!/usr/bin/env python3
"""Verifier for reactivate_suspended_user task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reactivate_suspended_user(traj, env_info, task_info):
    """
    Verify that James Rodriguez was reactivated while other users remain unchanged.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    score = 0
    feedback_parts = []
    
    # Parse values (default to string '0' or '1' to match DB output)
    james_now = str(result.get('james_now', '0')).strip()
    james_initial = str(result.get('james_initial', '0')).strip()
    
    admin_now = str(result.get('admin_now', '1')).strip()
    dispatch_now = str(result.get('dispatch_now', '1')).strip()
    sarah_now = str(result.get('sarah_now', '0')).strip()

    # Criterion 1: James Rodriguez reactivated (60 pts)
    if james_now == '1':
        score += 60
        feedback_parts.append("James Rodriguez reactivated")
    else:
        feedback_parts.append(f"James Rodriguez NOT reactivated (status={james_now})")

    # Criterion 2: Admin User still active (10 pts)
    if admin_now == '1':
        score += 10
        feedback_parts.append("Admin account safe")
    else:
        feedback_parts.append("Admin account improperly modified")

    # Criterion 3: Dispatch Officer still active (10 pts)
    if dispatch_now == '1':
        score += 10
        feedback_parts.append("Dispatch account safe")
    else:
        feedback_parts.append("Dispatch account improperly modified")

    # Criterion 4: Sarah Mitchell still pending (10 pts)
    # Important: Verify the agent didn't just "approve all"
    if sarah_now == '0':
        score += 10
        feedback_parts.append("Sarah Mitchell (pending) untouched")
    else:
        feedback_parts.append("Sarah Mitchell was incorrectly approved")

    # Criterion 5: State actually changed (10 pts)
    # Anti-gaming: Ensure it wasn't already 1 (setup error) and changed to 1
    if james_initial == '0' and james_now == '1':
        score += 10
        feedback_parts.append("Verified state change (0 -> 1)")
    elif james_initial == '1':
        feedback_parts.append("Setup Error: User was already active")
        # Invalidate the task if setup failed
        return {"passed": False, "score": 0, "feedback": "Task setup failed: Target user was already active."}
    else:
        # If james_now is 0, we already handled it in Criterion 1, but no points here
        pass

    passed = (score >= 60) and (james_now == '1')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }