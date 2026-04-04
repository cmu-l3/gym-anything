#!/usr/bin/env python3
"""
Verifier for merge_duplicate_records task.

Verifies that:
1. The duplicate record (Higher PID) is gone.
2. The master record (Lower PID) remains.
3. The total count of records for the patient is exactly 1.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_records(traj, env_info, task_info):
    """
    Verify the patient merge operation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Extract data
    master_exists = result.get("master_exists", False)
    duplicate_exists = result.get("duplicate_exists", True)
    total_count = result.get("total_records_count", 2)
    master_pid = result.get("master_pid", "Unknown")
    dup_pid = result.get("duplicate_pid", "Unknown")

    score = 0
    feedback = []
    
    # Criterion 1: Duplicate Eliminated (40 pts)
    if not duplicate_exists:
        score += 40
        feedback.append(f"Success: Duplicate PID {dup_pid} removed.")
    else:
        feedback.append(f"Fail: Duplicate PID {dup_pid} still exists.")

    # Criterion 2: Master Preserved (40 pts)
    if master_exists:
        score += 40
        feedback.append(f"Success: Master PID {master_pid} preserved.")
    else:
        feedback.append(f"Fail: Master PID {master_pid} was deleted/lost.")

    # Criterion 3: Clean State (20 pts)
    # Ensure we didn't just delete both or keep both
    if total_count == 1 and master_exists and not duplicate_exists:
        score += 20
        feedback.append("Success: Exactly one record remains.")
    elif total_count == 0:
        score = 0 # Critical failure
        feedback.append("Fail: All records were deleted.")
    elif total_count > 1:
        feedback.append(f"Fail: {total_count} records remain.")

    # Anti-gaming check: Backwards merge
    # If they kept duplicate and deleted master, score should be low
    if not master_exists and duplicate_exists and total_count == 1:
        score = 0
        feedback = ["Fail: Merged backwards! You kept the duplicate and deleted the master."]

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }