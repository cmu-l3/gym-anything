#!/usr/bin/env python3
"""
Verifier for create_relationship_type task.
Verifies that the agent created the specific Relationship Type in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_relationship_type(traj, env_info, task_info):
    """
    Verifies the creation of the 'Research Coordinator' relationship type.
    
    Criteria:
    1. Record exists in database (30 pts)
    2. 'A is to B' matches 'Research Coordinator' (20 pts)
    3. 'B is to A' matches 'Research Participant' (20 pts)
    4. Record is not retired (active) (10 pts)
    5. Record was created AFTER task start (Anti-gaming) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_a = metadata.get('expected_a_is_to_b', 'Research Coordinator')
    expected_b = metadata.get('expected_b_is_to_a', 'Research Participant')

    # Copy result JSON
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

    # Score Calculation
    score = 0
    feedback = []
    
    # 1. Check Existence
    if not result.get('found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No relationship type found matching 'Research Coordinator' or 'Research Participant'."
        }
    score += 30
    feedback.append("Relationship type record found.")

    # 2. Check Names
    actual_a = result.get('a_is_to_b', '').strip()
    actual_b = result.get('b_is_to_a', '').strip()
    
    if actual_a == expected_a:
        score += 20
        feedback.append(f"'A is to B' matches '{expected_a}'.")
    else:
        feedback.append(f"'A is to B' mismatch: expected '{expected_a}', got '{actual_a}'.")
        
    if actual_b == expected_b:
        score += 20
        feedback.append(f"'B is to A' matches '{expected_b}'.")
    else:
        feedback.append(f"'B is to A' mismatch: expected '{expected_b}', got '{actual_b}'.")

    # 3. Check Status (Not Retired)
    # retired is usually '0' or 'false' for active
    retired_val = str(result.get('retired', '')).lower()
    if retired_val in ['0', 'false', 'f']:
        score += 10
        feedback.append("Record is active (not retired).")
    else:
        feedback.append("Record is marked as retired.")

    # 4. Anti-gaming: Created during task
    if result.get('created_during_task', False):
        score += 20
        feedback.append("Record created during task session.")
    else:
        feedback.append("FAIL: Record creation timestamp predates task start (Anti-gaming check).")
        # Critical failure
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback)
        }

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }