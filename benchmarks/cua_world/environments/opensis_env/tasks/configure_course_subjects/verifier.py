#!/usr/bin/env python3
"""
Verifier for configure_course_subjects task.

Criteria:
1. 'Computer Science' subject exists in DB (40 pts)
2. 'Fine Arts' subject exists in DB (40 pts)
3. Both were created during the task (checked via ID > initial_max_id) (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_course_subjects(traj, env_info, task_info):
    """
    Verifies that the agent successfully added the required course subjects.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    initial_max_id = result.get("initial_max_id", 0)
    
    cs_data = result.get("computer_science", {})
    fa_data = result.get("fine_arts", {})
    
    # Check Computer Science
    if cs_data.get("found", False):
        if cs_data.get("id", 0) > initial_max_id:
            score += 40
            feedback_parts.append("Correctly created 'Computer Science'")
        else:
            score += 20
            feedback_parts.append("'Computer Science' exists but seems pre-existing (ID check failed)")
    else:
        feedback_parts.append("Failed to create 'Computer Science'")

    # Check Fine Arts
    if fa_data.get("found", False):
        if fa_data.get("id", 0) > initial_max_id:
            score += 40
            feedback_parts.append("Correctly created 'Fine Arts'")
        else:
            score += 20
            feedback_parts.append("'Fine Arts' exists but seems pre-existing (ID check failed)")
    else:
        feedback_parts.append("Failed to create 'Fine Arts'")

    # Bonus: Clean State / No Duplicates check
    # We verify that exactly 2 new records were created if we found both targets
    new_count = result.get("new_records_count", 0)
    targets_found = (1 if cs_data.get("found") else 0) + (1 if fa_data.get("found") else 0)
    
    if targets_found == 2:
        if new_count == 2:
            score += 20
            feedback_parts.append("Clean execution: Exactly 2 new records created")
        elif new_count > 2:
            score += 10
            feedback_parts.append(f"Minor deduction: {new_count} records created, expected 2")
    
    # Normalize score
    score = min(score, 100)
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }