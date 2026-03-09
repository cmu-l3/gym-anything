#!/usr/bin/env python3
"""Verifier for change_volume_password task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_change_volume_password(traj, env_info, task_info):
    """
    Verify that the VeraCrypt volume password was changed.

    Checks:
    1. Volume file still exists (not corrupted)
    2. Old password no longer works
    3. New password works
    4. Password change was actually performed (combined check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/veracrypt_password_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Volume file still exists
        if result.get('volume_exists'):
            criteria_met += 1
            feedback_parts.append("Volume file exists (not corrupted)")
        else:
            feedback_parts.append("Volume file is missing or corrupted")

        # Criterion 2: Old password no longer works
        if not result.get('old_password_works'):
            criteria_met += 1
            feedback_parts.append("Old password no longer works (correct)")
        else:
            feedback_parts.append("Old password still works (password not changed)")

        # Criterion 3: New password works
        if result.get('new_password_works'):
            criteria_met += 1
            feedback_parts.append("New password works (correct)")
        else:
            feedback_parts.append("New password does not work")

        # Criterion 4: Password change was actually performed
        if result.get('password_changed'):
            criteria_met += 1
            feedback_parts.append("Password change confirmed (old fails, new succeeds)")
        elif result.get('new_password_works') and not result.get('old_password_works'):
            # Fallback: both conditions met individually
            criteria_met += 1
            feedback_parts.append("Password change confirmed")
        else:
            feedback_parts.append("Password change not confirmed")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
