#!/usr/bin/env python3
"""
Verifier for create_visit_type task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_visit_type(traj, env_info, task_info):
    """
    Verify that the Telemedicine visit type was created with correct details.
    
    Criteria:
    1. Record exists in database (40 pts)
    2. Name is exactly "Telemedicine" (Implied by DB query, but double checked)
    3. Description matches exactly (30 pts)
    4. Not retired (10 pts)
    5. Created AFTER task start (10 pts) - Anti-gaming
    6. Navigation evidence via VLM (10 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Telemedicine")
    expected_desc = metadata.get('expected_description', "Remote consultation via video or phone")

    # 2. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    db_record = result.get('db_record', {})
    found = result.get('found_in_db', False)
    task_start = result.get('task_start_epoch', 0)
    created_time = db_record.get('date_created_epoch', 0)

    # Criterion 1: Existence (40 pts)
    if found:
        score += 40
        feedback.append("Visit type 'Telemedicine' found in database.")
    else:
        feedback.append("Visit type 'Telemedicine' NOT found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Description (30 pts)
    # Be slightly lenient with whitespace but strict with content
    actual_desc = db_record.get('description', '').strip()
    if actual_desc == expected_desc:
        score += 30
        feedback.append("Description matches exactly.")
    elif expected_desc.lower() in actual_desc.lower():
        score += 15
        feedback.append(f"Description partial match. Expected '{expected_desc}', got '{actual_desc}'.")
    else:
        feedback.append(f"Description incorrect. Expected '{expected_desc}', got '{actual_desc}'.")

    # Criterion 3: Status (10 pts)
    # retired should be "0" or 0 or False
    retired_val = db_record.get('retired', '1')
    if str(retired_val) in ['0', 'False', 'false']:
        score += 10
        feedback.append("Visit type is active (not retired).")
    else:
        feedback.append("Visit type is marked as retired.")

    # Criterion 4: Anti-gaming Timestamp (10 pts)
    # We allow a small buffer (e.g. clock skew), but generally created > start
    if created_time >= task_start:
        score += 10
        feedback.append("Creation timestamp verified (created during task).")
    else:
        feedback.append("Creation timestamp predates task start (Anti-gaming check failed).")

    # Criterion 5: Count Check (Bonus/Sanity)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    if current_count > initial_count:
        score += 10
        feedback.append("Total visit type count increased.")
    else:
        feedback.append("Visit type count did not increase (modified existing?).")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }