#!/usr/bin/env python3
"""
Verifier for remove_invalid_features task.

Verifies that:
1. The shapefile was modified during the task.
2. All records with POP_EST = -99 have been removed.
3. Valid records (POP_EST != -99) are preserved (file is not empty).
4. Feature count decreased by the expected amount.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_invalid_features(traj, env_info, task_info):
    """
    Verify the agent successfully removed features with POP_EST = -99.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
            
    # Extract metrics
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    final_count = result.get('final_count', 0)
    invalid_remaining = result.get('invalid_remaining', 0)
    valid_remaining = result.get('valid_remaining', 0)
    initial_count = result.get('initial_count', 0)
    initial_corrupted = result.get('initial_corrupted', 0)
    error = result.get('error')

    feedback_parts = []
    score = 0
    
    if error:
        return {"passed": False, "score": 0, "feedback": f"Error analyzing shapefile: {error}"}

    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Target shapefile not found"}

    # Criterion 1: File Modification (20 pts)
    if file_modified:
        score += 20
        feedback_parts.append("File changes saved")
    else:
        feedback_parts.append("File not modified (did you save edits?)")

    # Criterion 2: Invalid Features Removed (40 pts)
    # We expect 0 invalid records remaining
    if invalid_remaining == 0:
        score += 40
        feedback_parts.append("All invalid records removed")
    else:
        feedback_parts.append(f"{invalid_remaining} invalid records still present")

    # Criterion 3: Valid Features Preserved (20 pts)
    # We expect the file to not be empty and contain the rest of the countries
    expected_valid = initial_count - initial_corrupted
    # Allow a small margin of error (e.g. if agent accidentally deleted 1-2 extra valid ones)
    if valid_remaining >= (expected_valid - 5) and valid_remaining > 0:
        score += 20
        feedback_parts.append(f"Valid data preserved ({valid_remaining} records)")
    elif valid_remaining > 0:
        score += 10
        feedback_parts.append(f"Some valid data lost ({valid_remaining} remaining, expected ~{expected_valid})")
    else:
        feedback_parts.append("All data was deleted!")

    # Criterion 4: Feature Count Reduction (20 pts)
    # The count should have gone down
    if final_count < initial_count:
        score += 20
        feedback_parts.append(f"Feature count reduced ({initial_count} -> {final_count})")
    else:
        feedback_parts.append("Feature count did not decrease")

    # Final Pass/Fail
    # Must have removed invalid data AND kept valid data AND modified the file
    passed = (invalid_remaining == 0) and (valid_remaining > 50) and file_modified and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }