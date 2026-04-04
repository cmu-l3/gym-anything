#!/usr/bin/env python3
"""
Verifier for Correct Diagnosis Error task in OSCAR EMR.

Criteria:
1. Target Diagnosis (Secondary Hypertension/405) MUST be active. (40 pts)
2. Old Diagnosis (Essential Hypertension/401) MUST NOT be active. (40 pts)
3. Data Integrity (20 pts):
   - Best case: The original record was updated (ID preserved).
   - Good case: Original deleted/resolved, new one added.
   - Fail case: Both exist (duplicates).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_correct_diagnosis_error(traj, env_info, task_info):
    """
    Verify that the diagnosis was corrected in the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback_parts = []
    
    # Extract data
    target_found = result.get('target_found', False)
    target_id = result.get('target_id', '')
    initial_dx_id = result.get('initial_dx_id', '')
    original_status = result.get('original_dx_status', '')
    active_old_count = int(result.get('active_old_diagnosis_count', 0))

    # CRITERION 1: Target Diagnosis Present (40 pts)
    if target_found:
        score += 40
        feedback_parts.append("Success: 'Secondary Hypertension' (405) is active.")
    else:
        feedback_parts.append("Fail: 'Secondary Hypertension' (405) not found in active records.")

    # CRITERION 2: Old Diagnosis Removed/Resolved (40 pts)
    # Passed if active_old_count is 0
    if active_old_count == 0:
        score += 40
        feedback_parts.append("Success: 'Essential Hypertension' (401) is no longer active.")
    else:
        feedback_parts.append(f"Fail: 'Essential Hypertension' (401) is still active ({active_old_count} records).")

    # CRITERION 3: Method / Data Integrity (20 pts)
    # Bonus for clean data (updating the row vs deleting and adding)
    if target_found and active_old_count == 0:
        if target_id == initial_dx_id:
            score += 20
            feedback_parts.append("Perfect: Existing record was updated directly.")
        else:
            # They deleted the old one and added a new one. This is valid but slightly less "clean" if history is lost,
            # but usually acceptable in EMRs. We give full points if the result is correct.
            score += 20
            feedback_parts.append("Good: Old record resolved/deleted and new record created.")
    elif target_found and active_old_count > 0:
        # Penalize for duplicates (leaving the error while adding correct one)
        feedback_parts.append("Warning: Created duplicate entry instead of correcting the error.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }