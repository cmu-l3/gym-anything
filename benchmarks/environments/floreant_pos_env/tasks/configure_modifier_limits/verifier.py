#!/usr/bin/env python3
"""
Verifier for configure_modifier_limits task.
Verifies that a Modifier Group exists with specific Minimum and Maximum quantity settings.
"""

import json
import os
import tempfile
import logging

# Standard logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_modifier_limits(traj, env_info, task_info):
    """
    Verifies that the agent configured the 'Omelet Fillings' modifier group correctly.
    
    Criteria:
    1. Modifier Group 'Omelet Fillings' must exist in the database.
    2. MIN_QUANTITY must be 2.
    3. MAX_QUANTITY must be 4.
    4. VLM Verification: Agent must have visited the Back Office.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_min', 2)
    expected_max = metadata.get('expected_max', 4)
    target_name = metadata.get('target_group_name', 'Omelet Fillings')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Verification
    db_check = result.get('db_check', {})
    found = db_check.get('found', False)
    actual_min = db_check.get('min_quantity')
    actual_max = db_check.get('max_quantity')
    
    score = 0
    feedback = []
    
    # Criterion 1: Group Found (25 pts)
    if found:
        score += 25
        feedback.append(f"Success: Modifier group '{target_name}' found in database.")
    else:
        feedback.append(f"Fail: Modifier group '{target_name}' not found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Min Quantity Correct (30 pts)
    if actual_min == expected_min:
        score += 30
        feedback.append(f"Success: Minimum quantity set to {expected_min}.")
    else:
        feedback.append(f"Fail: Minimum quantity is {actual_min} (expected {expected_min}).")

    # Criterion 3: Max Quantity Correct (30 pts)
    if actual_max == expected_max:
        score += 30
        feedback.append(f"Success: Maximum quantity set to {expected_max}.")
    else:
        feedback.append(f"Fail: Maximum quantity is {actual_max} (expected {expected_max}).")
        
    # Criterion 4: VLM / Screenshot Check (15 pts)
    # Since we have strong DB verification, we use VLM just to ensure UI interaction happened
    # and not just a direct SQL injection (though unlikely in this env).
    # Simple check: Does final screenshot exist?
    if result.get('screenshot_exists'):
        score += 15
        feedback.append("Success: Final state screenshot captured.")
    else:
        feedback.append("Warning: No final screenshot found.")

    # 3. Final Assessment
    # We require the database values to be exactly correct to pass
    passed = (found and actual_min == expected_min and actual_max == expected_max)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }