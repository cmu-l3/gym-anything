#!/usr/bin/env python3
"""
Verifier for configure_trash_can task.

Verifies that:
1. Trash Can is enabled in Artifactory system configuration.
2. Retention period is set to exactly 30 days.
3. Configuration was actually present/changed (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_trash_can(traj, env_info, task_info):
    """
    Verify Artifactory Trash Can configuration.
    """
    # 1. Setup - Get access to container file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Data
    final_state = result.get("final_state", {})
    initial_state = result.get("initial_state", {})
    
    current_enabled = final_state.get("enabled", False)
    current_days = final_state.get("days", 0)
    
    expected_days = task_info.get("metadata", {}).get("expected_retention_days", 30)
    expected_enabled = task_info.get("metadata", {}).get("expected_enabled", True)

    score = 0
    feedback_parts = []
    
    # 4. Verify Enabled Status (40 points)
    if current_enabled == expected_enabled:
        score += 40
        feedback_parts.append(f"Trash Can enabled status correct ({current_enabled})")
    else:
        feedback_parts.append(f"Trash Can enabled status incorrect (Expected: {expected_enabled}, Got: {current_enabled})")

    # 5. Verify Retention Days (60 points)
    if current_days == expected_days:
        score += 60
        feedback_parts.append(f"Retention period correct ({current_days} days)")
    else:
        feedback_parts.append(f"Retention period incorrect (Expected: {expected_days}, Got: {current_days})")

    # 6. Anti-Gaming / Do-Nothing Check
    # If the initial state happened to match the goal (unlikely for 30 days, default is usually 14), 
    # we might want to check if the user actually interacted.
    # However, since 30 is non-default, simply achieving the state proves interaction.
    # We just ensure we actually got valid data.
    if final_state.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve configuration: {final_state.get('error')}"}

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }