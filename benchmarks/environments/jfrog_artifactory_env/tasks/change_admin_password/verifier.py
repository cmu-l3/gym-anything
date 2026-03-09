#!/usr/bin/env python3
"""
Verifier for change_admin_password task.

Verification Logic:
1. Primary: REST API Probe
   - New Password ('SecureAdmin2024!') MUST return HTTP 200 (50 points)
   - Old Password ('password') MUST return HTTP 401 or 403 (30 points)
2. Secondary: Process Integrity
   - Screenshot must exist (10 points)
   - State must have actually changed (10 points)

Pass Threshold: 80 points (Requires both passwords to behave correctly)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_admin_password(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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
    
    # Extract values
    new_status = result.get('new_password_auth_status', 0)
    old_status = result.get('old_password_auth_status', 0)
    screenshot_exists = result.get('screenshot_exists', False)
    initial_status = result.get('initial_auth_status', 0)

    # Criterion 1: New Password Works (50 points)
    if new_status == 200:
        score += 50
        feedback_parts.append("New password authenticates successfully (+50)")
    else:
        feedback_parts.append(f"New password failed authentication (HTTP {new_status})")

    # Criterion 2: Old Password Rejected (30 points)
    # 401: Unauthorized, 403: Forbidden (Locked)
    if old_status in [401, 403]:
        score += 30
        feedback_parts.append("Old password rejected (+30)")
    elif old_status == 200:
        feedback_parts.append("Old password still works! (Security Risk)")
    else:
        feedback_parts.append(f"Old password check returned unexpected code: {old_status}")

    # Criterion 3: Evidence & Anti-Gaming (20 points)
    if screenshot_exists:
        score += 10
        feedback_parts.append("Screenshot evidence present (+10)")
    else:
        feedback_parts.append("No screenshot evidence")

    # Verify state actually changed (prevent 'do nothing' if initial state was somehow broken)
    # If old status == 200 (fail) and new status != 200 (fail), score is low.
    # We check if the status codes are DIFFERENT to confirm action.
    if new_status != old_status:
        score += 10
        feedback_parts.append("Authentication state changed (+10)")
    else:
        feedback_parts.append("No change in authentication state detected")

    # Final Evaluation
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }