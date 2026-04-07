#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_applicants(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Transferred the note (visa sponsorship) to the new application.
    2. Archived the old application.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []

    # Check 1: Old App Archived (40 pts)
    # The old app should exist and active should be False
    if result.get("old_app_exists", False):
        if not result.get("old_app_active", True):
            score += 40
            feedback.append("Old application successfully archived.")
        else:
            feedback.append("Old application is still active (not archived).")
    else:
        feedback.append("Old application not found (deleted?).")

    # Check 2: New App Active (10 pts)
    # The new app should remain active
    if result.get("new_app_active", False):
        score += 10
        feedback.append("New application is active.")
    else:
        feedback.append("New application was archived or deleted (should remain active).")

    # Check 3: Note Transfer (50 pts total)
    if result.get("new_note_found", False):
        score += 50
        feedback.append("Visa sponsorship note found on new application.")
    else:
        feedback.append("Visa sponsorship note NOT found on new application.")

    # Final Pass/Fail
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }