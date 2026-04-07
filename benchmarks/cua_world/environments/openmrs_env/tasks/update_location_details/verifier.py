#!/usr/bin/env python3
"""
Verifier for update_location_details task.

Criteria:
1. Location 'Laboratory' must exist (20 pts)
2. Description must match target text exactly (60 pts)
3. Record must have been modified during the task window (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_location_details(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_description = metadata.get('target_description', "Main clinical pathology lab. Open 24/7 for emergency samples.")
    
    # 2. Retrieve result JSON
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

    # 3. Evaluate
    score = 0
    feedback_parts = []
    
    location_found = result.get('location_found', False)
    current_desc = result.get('current_description', "").strip()
    modified_during_task = result.get('modified_during_task', False)
    
    # Criterion 1: Location Found (20 pts)
    if location_found:
        score += 20
        feedback_parts.append("Location 'Laboratory' found")
    else:
        feedback_parts.append("Location 'Laboratory' NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Description Content (60 pts)
    # We normalize spaces for comparison to be slightly forgiving of double spaces
    norm_target = " ".join(target_description.split())
    norm_current = " ".join(current_desc.split())
    
    if norm_current == norm_target:
        score += 60
        feedback_parts.append("Description updated correctly")
    else:
        feedback_parts.append(f"Description mismatch. Expected: '{target_description}', Got: '{current_desc}'")

    # Criterion 3: Anti-Gaming Timestamp Check (20 pts)
    # Only award if the content is also correct (or at least changed), otherwise 
    # simply saving without changes shouldn't get points if the goal wasn't met.
    if modified_during_task:
        score += 20
        feedback_parts.append("Modification recorded during task")
    else:
        feedback_parts.append("No modification detected during task execution")

    # Final Pass/Fail
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }