#!/usr/bin/env python3
"""
Verifier for configure_channel_notifications task.

Verifies:
1. Desktop notifications set to 'mentions'
2. Mobile notifications set to 'mentions'
3. Email notifications set to 'nothing'
4. Settings were updated AFTER task start (anti-gaming)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_channel_notifications(traj, env_info, task_info):
    """
    Verify channel notification settings via API result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_desktop = metadata.get('expected_desktop', 'mentions')
    expected_mobile = metadata.get('expected_mobile', 'mentions')
    expected_email = metadata.get('expected_email', 'nothing')

    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    settings_found = result.get('settings_found', False)
    
    if not settings_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve channel subscription settings. Did the agent log in?"
        }

    # Setup/Login successful (10 pts)
    score += 10
    
    # Check Desktop (30 pts)
    actual_desktop = result.get('desktop_notifications', 'default')
    if actual_desktop == expected_desktop:
        score += 30
        feedback_parts.append(f"Desktop correct ({actual_desktop})")
    else:
        feedback_parts.append(f"Desktop incorrect (expected {expected_desktop}, got {actual_desktop})")

    # Check Mobile (30 pts)
    actual_mobile = result.get('mobile_notifications', 'default')
    if actual_mobile == expected_mobile:
        score += 30
        feedback_parts.append(f"Mobile correct ({actual_mobile})")
    else:
        feedback_parts.append(f"Mobile incorrect (expected {expected_mobile}, got {actual_mobile})")

    # Check Email (30 pts)
    actual_email = result.get('email_notifications', 'default')
    if actual_email == expected_email:
        score += 30
        feedback_parts.append(f"Email correct ({actual_email})")
    else:
        feedback_parts.append(f"Email incorrect (expected {expected_email}, got {actual_email})")

    # Anti-gaming: Check timestamp
    updated_at = result.get('updated_at_timestamp', 0)
    task_start = result.get('task_start_timestamp', 0)
    
    # Only penalize if score is high (meaning they have correct values)
    # If updated_at is 0, it might mean the field was missing, handle gracefully
    if score >= 70:
        if updated_at > task_start:
            feedback_parts.append("Settings updated during task")
        elif updated_at > 0:
            # If timestamp exists but is old, they didn't change anything (lucky guess or pre-set)
            # But setup_task.sh resets them, so this implies they didn't save new changes
            score = 10 # Reset score, only keep login points
            feedback_parts.append("FAIL: Settings matched but were NOT updated during this task session (stale data).")
        else:
            # Timestamp missing/zero - give benefit of doubt if values are correct, 
            # or could penalize slightly. Rocket.Chat should return it.
            feedback_parts.append("Warning: Could not verify update timestamp.")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }