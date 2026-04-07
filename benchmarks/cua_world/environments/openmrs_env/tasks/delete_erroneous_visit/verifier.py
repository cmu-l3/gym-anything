#!/usr/bin/env python3
"""
Verifier for delete_erroneous_visit task.
Verifies that the specific erroneous visit was voided in the database
without deleting other patient data.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_erroneous_visit(traj, env_info, task_info):
    """
    Verify the visit deletion task.
    
    Criteria:
    1. Target visit is voided (deleted) in DB. (35 pts)
    2. Active visit count decreased by exactly 1. (15 pts)
    3. No other visits were voided (Collateral damage check). (15 pts)
    4. Void reason was provided (not empty). (15 pts)
    5. Action happened during task window (Anti-gaming). (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    is_voided = result.get('is_voided', False)
    void_reason = result.get('void_reason', '').strip()
    void_timestamp = result.get('void_timestamp', 0)
    task_start = result.get('task_start_timestamp', 0)
    initial_count = result.get('initial_active_count', 0)
    final_count = result.get('final_active_count', 0)
    collateral_count = result.get('collateral_void_count', 0)

    # Criterion 1: Target visit is voided (35 pts)
    if is_voided:
        score += 35
        feedback_parts.append("Target visit successfully voided")
    else:
        feedback_parts.append("Target visit is NOT voided")

    # Criterion 2: Count check (15 pts)
    expected_count = initial_count - 1
    if final_count == expected_count:
        score += 15
        feedback_parts.append("Active visit count decreased correctly")
    else:
        feedback_parts.append(f"Visit count mismatch (Initial: {initial_count}, Final: {final_count})")

    # Criterion 3: Collateral damage (15 pts)
    if collateral_count == 0:
        score += 15
        feedback_parts.append("No other visits were deleted")
    else:
        feedback_parts.append(f"WARNING: {collateral_count} other visit(s) were incorrectly deleted")

    # Criterion 4: Void reason (15 pts)
    # OpenMRS UI requires a reason, but API might not. We check if one was recorded.
    if is_voided and len(void_reason) > 0:
        score += 15
        feedback_parts.append(f"Void reason recorded: '{void_reason}'")
    elif is_voided:
        feedback_parts.append("No void reason recorded (database field empty)")

    # Criterion 5: Anti-gaming Timestamp (20 pts)
    # Ensure the void action happened AFTER the task started
    if is_voided and void_timestamp >= task_start:
        score += 20
        feedback_parts.append("Action performed during task window")
    elif is_voided:
        feedback_parts.append("FAIL: Visit appears to have been voided before task started")

    passed = (score >= 65) and is_voided and (collateral_count == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }