#!/usr/bin/env python3
"""
Verifier for archive_withdrawn_applications task.

Verification Logic:
1. Primary: Database check via XML-RPC (exported JSON)
   - Active applications for 'James Miller' must be 0 (40 pts)
   - Archived applications for 'James Miller' must be 3 (30 pts)
   - Total applications must be 3 (ensures no deletion) (20 pts)
2. Secondary: Anti-gaming
   - Checks that records were actually modified (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_withdrawn_applications(traj, env_info, task_info):
    """
    Verify that James Miller's applications were archived but not deleted.
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

    # Check for script errors
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []
    
    active_count = result.get('active_count', -1)
    archived_count = result.get('archived_count', -1)
    total_count = result.get('total_count', -1)
    
    expected_total = 3

    # Criterion 1: Zero Active Applications (40 pts)
    if active_count == 0:
        score += 40
        feedback.append("Success: No active applications remain.")
    else:
        feedback.append(f"Fail: {active_count} active applications still exist (expected 0).")

    # Criterion 2: Three Archived Applications (30 pts)
    if archived_count == 3:
        score += 30
        feedback.append("Success: 3 applications found in archive.")
    elif archived_count > 0:
        score += 10
        feedback.append(f"Partial: Only {archived_count} applications archived (expected 3).")
    else:
        feedback.append("Fail: No applications found in archive.")

    # Criterion 3: No Data Loss / Deletion (20 pts)
    if total_count == expected_total:
        score += 20
        feedback.append("Success: All records preserved (none deleted).")
    else:
        feedback.append(f"Fail: Data loss detected. Total records: {total_count} (expected {expected_total}).")

    # Criterion 4: Modification Check (10 pts)
    if result.get('modified_recently', False) and score > 0:
        score += 10
        feedback.append("Action verified.")

    # Pass Threshold
    passed = (score >= 90)  # Strict pass: must archive all and delete none
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }