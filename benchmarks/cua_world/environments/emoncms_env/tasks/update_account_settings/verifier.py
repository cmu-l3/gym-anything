#!/usr/bin/env python3
"""
Verifier for update_account_settings task in Emoncms.

Verifies:
1. Timezone updated to 'Europe/London' (50 pts)
2. Email updated to 'admin@greenbuilding.co.uk' (50 pts)
3. Anti-gaming: Checks that values actually changed from start state.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_account_settings(traj, env_info, task_info):
    """
    Verify that the Emoncms admin account settings were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_timezone = metadata.get('expected_timezone', 'Europe/London')
    expected_email = metadata.get('expected_email', 'admin@greenbuilding.co.uk')

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

    # Extract values
    current_timezone = result.get('current_timezone', '')
    current_email = result.get('current_email', '')
    initial_timezone = result.get('initial_timezone', '')
    initial_email = result.get('initial_email', '')
    
    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Verify Timezone (50 pts)
    if current_timezone == expected_timezone:
        score += 50
        feedback_parts.append(f"Timezone correctly set to '{expected_timezone}'")
    else:
        # Partial credit if they changed it, but to the wrong thing (and not just left as default)
        if current_timezone != initial_timezone and current_timezone != "":
             score += 10
             feedback_parts.append(f"Timezone changed to '{current_timezone}' (expected '{expected_timezone}')")
        else:
             feedback_parts.append(f"Timezone incorrect (is '{current_timezone}', expected '{expected_timezone}')")

    # 2. Verify Email (50 pts)
    if current_email == expected_email:
        score += 50
        feedback_parts.append(f"Email correctly set to '{expected_email}'")
    else:
        # Partial credit if they changed it
        if current_email != initial_email and current_email != "":
            score += 10
            feedback_parts.append(f"Email changed to '{current_email}' (expected '{expected_email}')")
        else:
            feedback_parts.append(f"Email incorrect (is '{current_email}', expected '{expected_email}')")

    # 3. Anti-gaming / Sanity Checks
    if score > 0:
        if current_timezone == initial_timezone and current_email == initial_email:
             # This technically shouldn't happen if we award points based on matching expected, 
             # unless expected == initial (which setup_task.sh prevents).
             # But as a safeguard:
             score = 0
             feedback_parts.append("ANTI-GAMING: No changes detected from initial state.")

    passed = (score == max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }