#!/usr/bin/env python3
"""
Verifier for add_relationship task.

Checks:
1. Relationship exists in DB between correct patients (40 pts)
2. Relationship type is 'Sibling' (30 pts)
3. Relationship created AFTER task start (15 pts)
4. Total relationship count increased (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_relationship(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # 1. Check if relationship exists (40 pts)
    rel_found = result.get('relationship_found', False)
    if rel_found:
        score += 40
        feedback_parts.append("Relationship link found between patients.")
    else:
        feedback_parts.append("No relationship link found between the specified patients.")
        return {"passed": False, "score": 0, "feedback": "Task failed: " + " ".join(feedback_parts)}

    # 2. Check relationship type (30 pts)
    rel_type = result.get('relationship_type', '').lower()
    if 'sibling' in rel_type:
        score += 30
        feedback_parts.append("Relationship type is correctly set to Sibling.")
    else:
        feedback_parts.append(f"Incorrect relationship type: found '{result.get('relationship_type')}', expected 'Sibling'.")

    # 3. Check timestamp (anti-gaming) (15 pts)
    created_ts = int(result.get('creation_timestamp', 0))
    start_ts = int(result.get('task_start_time', 0))
    
    if created_ts > start_ts:
        score += 15
        feedback_parts.append("Relationship created during task window.")
    else:
        feedback_parts.append("Relationship timestamp predates task start (pre-existing data?).")

    # 4. Check count increase (15 pts)
    initial = int(result.get('initial_count', 0))
    final = int(result.get('final_count', 0))
    
    if final > initial:
        score += 15
        feedback_parts.append("Total relationship count increased.")
    else:
        feedback_parts.append("Total relationship count did not increase.")

    passed = score >= 70  # Threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }