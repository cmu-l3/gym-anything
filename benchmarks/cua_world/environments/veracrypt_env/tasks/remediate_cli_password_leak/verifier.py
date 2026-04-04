#!/usr/bin/env python3
"""
Verifier for remediate_cli_password_leak task.

Criteria:
1. Volume must mount with the new password (50 pts).
2. Volume must NOT mount with the old leaked password (30 pts).
3. The bash history file must not contain the leaked password (20 pts).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_remediate_cli_password_leak(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Error loading result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # Criterion 1: New Password Works (50 pts)
    if result.get('new_password_works'):
        score += 50
        feedback_parts.append("Success: Volume mounts with new password")
    else:
        feedback_parts.append("Failure: Volume does not mount with 'SecuredCredential2025!'")

    # Criterion 2: Old Password Invalidated (30 pts)
    # Note: If new password works, usually old doesn't, unless they added a keyfile or something weird.
    # But specifically, we check old_password_works is False.
    if not result.get('old_password_works'):
        score += 30
        feedback_parts.append("Success: Old leaked password rejected")
    else:
        # If old password still works, they didn't change it (or added a second slot, though standard VC is 1 pass)
        feedback_parts.append("Failure: Old leaked password still opens the volume")

    # Criterion 3: History Sanitized (20 pts)
    if result.get('history_sanitized'):
        score += 20
        feedback_parts.append("Success: Leaked password removed from history")
    else:
        feedback_parts.append("Failure: Leaked password still found in .bash_history")

    # Final logic
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }