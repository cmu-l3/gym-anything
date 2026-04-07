#!/usr/bin/env python3
"""
Verifier for deactivate_leaver_accounts task.
Checks if specific users were deleted or retained according to the instruction note.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_leaver_accounts(traj, env_info, task_info):
    """
    Verify that:
    1. mholloway is deleted (35 pts)
    2. clille is deleted (35 pts)
    3. sdhawan is RETAINED (30 pts)
    """
    # 1. Setup - Get Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    users = result.get('users', {})
    mh_exists = users.get('mholloway_exists', True)
    cl_exists = users.get('clille_exists', True)
    sd_exists = users.get('sdhawan_exists', False)
    admin_exists = users.get('administrator_exists', False)

    # 3. Sanity Check
    if not admin_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAILURE: The Administrator account was deleted. This is a catastrophic failure."
        }

    # 4. Scoring
    score = 0
    feedback_parts = []

    # Criterion 1: Marcus Holloway (mholloway) deleted
    if not mh_exists:
        score += 35
        feedback_parts.append("Marcus Holloway successfully deleted.")
    else:
        feedback_parts.append("Failed: Marcus Holloway (mholloway) still exists.")

    # Criterion 2: Clara Lille (clille) deleted
    if not cl_exists:
        score += 35
        feedback_parts.append("Clara Lille successfully deleted.")
    else:
        feedback_parts.append("Failed: Clara Lille (clille) still exists.")

    # Criterion 3: Sitara Dhawan (sdhawan) retained
    if sd_exists:
        score += 30
        feedback_parts.append("Sitara Dhawan correctly retained.")
    else:
        feedback_parts.append("Failed: Sitara Dhawan was incorrectly deleted (negative constraint violation).")

    # 5. Final Result
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }