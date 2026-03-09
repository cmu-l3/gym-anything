#!/usr/bin/env python3
"""
Verifier for enable_user_locking task.
Verifies that the Artifactory system configuration reflects the requested security policies.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_user_locking(traj, env_info, task_info):
    """
    Verify user locking configuration.
    
    Criteria:
    1. User Locking is Enabled (40 pts)
    2. Max Login Attempts == 3 (30 pts)
    3. Lockout Time == 1 hour (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_enabled = metadata.get('expected_enabled', True)
    expected_max_attempts = metadata.get('expected_max_attempts', 3)
    expected_lockout_time = metadata.get('expected_lockout_time', 1)

    # Load result from container
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

    # Check if config was retrieved
    if not result.get('config_xml_retrieved', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve Artifactory system configuration. Ensure Artifactory is running."
        }

    parsed = result.get('parsed_config', {})
    if not parsed.get('found_policy', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "User Lock Policy section not found in system configuration."
        }

    score = 0
    feedback_parts = []
    
    # Criterion 1: Enabled
    actual_enabled = parsed.get('enabled', False)
    if actual_enabled == expected_enabled:
        score += 40
        feedback_parts.append("User Locking ENABLED")
    else:
        feedback_parts.append(f"User Locking NOT enabled (found: {actual_enabled})")

    # Criterion 2: Max Attempts
    actual_attempts = parsed.get('max_attempts', -1)
    if actual_attempts == expected_max_attempts:
        score += 30
        feedback_parts.append(f"Max Attempts set to {expected_max_attempts}")
    else:
        feedback_parts.append(f"Max Attempts mismatch (found: {actual_attempts}, expected: {expected_max_attempts})")

    # Criterion 3: Lockout Time
    actual_time = parsed.get('lockout_time', -1)
    if actual_time == expected_lockout_time:
        score += 30
        feedback_parts.append(f"Lockout Time set to {expected_lockout_time} hr")
    else:
        feedback_parts.append(f"Lockout Time mismatch (found: {actual_time}, expected: {expected_lockout_time})")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }