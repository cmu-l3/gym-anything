#!/usr/bin/env python3
"""
Verifier for configure_request_archiving task.
Checks if the Data Archiving policy is correctly enabled and configured in the database.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_request_archiving(traj, env_info, task_info):
    """
    Verify Request Archiving configuration.
    
    Criteria:
    1. Archiving must be ENABLED for Requests (40 pts)
    2. Archiving days must be set to 365 (40 pts)
    3. Configuration must be valid/saved (implied by 1&2) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_days = str(metadata.get('expected_days', 365))
    
    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Check 1: App Running (Pre-requisite)
    if not result.get('app_running', False):
        return {"passed": False, "score": 0, "feedback": "ServiceDesk Plus was not running at verification time."}

    # Check 2: Archiving Enabled (40 pts)
    is_enabled = result.get('db_archiving_enabled', False)
    if is_enabled:
        score += 40
        feedback_parts.append("Archiving is enabled")
    else:
        feedback_parts.append("Archiving is NOT enabled")

    # Check 3: Correct Days (40 pts)
    # The setup script resets this to 1000, so 365 means the agent changed it.
    actual_days = str(result.get('db_archiving_days', '0')).strip()
    
    if actual_days == expected_days:
        score += 40
        feedback_parts.append(f"Retention period set correctly to {actual_days} days")
    else:
        feedback_parts.append(f"Retention period mismatch (expected {expected_days}, got {actual_days})")

    # Check 4: Configuration Valid (20 pts)
    # If both enabled and days are correct, the config is fully valid.
    # We give partial credit here if at least one parameter was changed from default/setup.
    if is_enabled and actual_days == expected_days:
        score += 20
        feedback_parts.append("Configuration saved successfully")
    elif is_enabled or actual_days == expected_days:
        score += 10
        feedback_parts.append("Partial configuration saved")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }