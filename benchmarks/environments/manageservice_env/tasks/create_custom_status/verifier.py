#!/usr/bin/env python3
"""
Verifier for Create Custom Request Status task.

Verifies:
1. Status 'Waiting for Vendor' exists in database.
2. Status Type is 'PENDING' (critical for SLA stopping).
3. Status was created during the task (ID > initial max ID).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_status(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_status_name', 'Waiting for Vendor')
    target_type = metadata.get('target_status_type', 'PENDING')

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
    
    # Check 1: Status Found
    status_found = result.get("status_found", False)
    status_name = result.get("status_name", "")
    
    if status_found and status_name.lower() == target_name.lower():
        score += 40
        feedback_parts.append(f"Status '{target_name}' created successfully")
    else:
        feedback_parts.append(f"Status '{target_name}' NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Status Type (Critical for SLA)
    status_type = result.get("status_type", "").upper()
    if target_type in status_type:
        score += 40
        feedback_parts.append("Status type configured correctly as 'Pending' (SLA timer stops)")
    else:
        feedback_parts.append(f"Incorrect status type: Found '{status_type}', expected '{target_type}'. The SLA timer will not pause.")

    # Check 3: Anti-gaming (Created during task)
    status_id = int(result.get("status_id", 0))
    initial_max_id = int(result.get("initial_max_id", 0))
    
    if status_id > initial_max_id:
        score += 20
        feedback_parts.append("Status created during current session")
    else:
        feedback_parts.append(f"Status ID ({status_id}) is not new (Initial Max: {initial_max_id})")
        # If it wasn't new, we penalize significantly but don't fail if properties are perfect, 
        # though for a creation task this usually means they didn't do the work.
        score = max(0, score - 50) 

    passed = score >= 80  # Requires correct name AND correct type

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }