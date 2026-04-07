#!/usr/bin/env python3
"""
Verifier for clean_orphan_origins_db task.

Evaluates:
1. Did the agent document the correct orphans in the file?
2. Did the agent delete the unassociated origins from the database?
3. Did the agent safely preserve valid catalog events?
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_orphan_origins(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_orphan_ids = metadata.get('orphan_ids', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    file_exists = result.get('file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_contents = result.get('file_contents', '')
    targets_remaining = result.get('targets_remaining', -1)
    valid_events_count = result.get('valid_events_count', -1)

    found_ids_list = [item.strip() for item in file_contents.split(',') if item.strip()]
    
    # 1. Output File Creation (10 pts)
    if file_exists and file_created_during_task:
        score += 10
        feedback.append("File created successfully during task (+10)")
    elif file_exists:
        score += 5
        feedback.append("File exists but timestamp issue (+5)")
    else:
        feedback.append("Documentation file not found")

    # 2. Correct Documentation of Orphans (30 pts)
    correct_identifications = 0
    incorrect_identifications = 0

    for f_id in found_ids_list:
        if f_id in expected_orphan_ids:
            correct_identifications += 1
        else:
            incorrect_identifications += 1

    if file_exists:
        if correct_identifications == len(expected_orphan_ids) and incorrect_identifications == 0:
            score += 30
            feedback.append("Perfectly documented all orphan IDs (+30)")
        else:
            partial = max(0, (correct_identifications * 10) - (incorrect_identifications * 10))
            score += partial
            feedback.append(f"Documented {correct_identifications}/{len(expected_orphan_ids)} correct IDs, {incorrect_identifications} incorrect (+{partial})")

    # 3. Successful DB Cleanup (40 pts)
    if targets_remaining == 0:
        score += 40
        feedback.append("All injected orphans successfully deleted from database (+40)")
    elif targets_remaining > 0:
        deleted = len(expected_orphan_ids) - targets_remaining
        if deleted > 0:
            partial_del = int((deleted / len(expected_orphan_ids)) * 40)
            score += partial_del
            feedback.append(f"Partially deleted {deleted}/{len(expected_orphan_ids)} orphans (+{partial_del})")
        else:
            feedback.append("No orphans were deleted from the database")
    else:
        feedback.append("Failed to query database state for cleanup verification")

    # 4. Safe Database Manipulation (20 pts)
    if valid_events_count >= 1:
        score += 20
        feedback.append("Main catalog events safely preserved (+20)")
    else:
        feedback.append("CRITICAL FAILURE: Main catalog events were destroyed/deleted")
        # Severe penalty if they blew away the valid data
        score = min(score, 30)

    # Assess passing state
    # Must achieve at least 80 points (means they preserved data, documented them, and deleted most/all)
    key_criteria_met = (targets_remaining == 0) and (valid_events_count >= 1) and file_exists
    passed = (score >= 80) and key_criteria_met

    if passed:
        feedback.insert(0, "SUCCESS: Orphans cleanly identified and removed.")
    else:
        feedback.insert(0, "FAILED: Did not fully complete safe cleanup workflow.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "targets_remaining": targets_remaining,
            "valid_events": valid_events_count,
            "correct_ids_logged": correct_identifications
        }
    }