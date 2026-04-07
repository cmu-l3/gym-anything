#!/usr/bin/env python3
"""
Verifier for edit_department task.

Criteria:
1. Department Name Changed (30 pts): The department at the original ID should now be named "Haul Road Patrol".
2. Short Name Changed (25 pts): The department at the original ID should now be "HRP".
3. Old Name Removed (15 pts): No department named "San Andreas Highway Patrol" should exist.
4. ID Preserved (15 pts): The new name should be associated with the ORIGINAL ID (proof of edit vs recreate).
5. Associations Intact (15 pts): The user_departments links should still exist for this ID.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_department(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Haul Road Patrol")
    expected_short = metadata.get('expected_short_name', "HRP")

    # Load result from container
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
    
    current = result.get('current_state_at_id', {})
    global_checks = result.get('global_checks', {})
    
    # 1. ID Preserved check (Prerequisite for full points on others)
    id_preserved = current.get('exists', False)
    if id_preserved:
        score += 15
        feedback_parts.append("Department ID preserved (edit confirmed)")
    else:
        feedback_parts.append("Department ID lost (likely deleted and recreated)")

    # 2. Check Name at ID (Preferred) vs Global
    curr_name = current.get('name', '').strip()
    if curr_name == expected_name:
        score += 30
        feedback_parts.append(f"Name correctly changed to '{expected_name}'")
    elif global_checks.get('new_name_count', 0) > 0:
        # Created new instead of editing
        score += 15 # Partial credit
        feedback_parts.append(f"Name '{expected_name}' found, but not at original ID (deleted/recreated?)")
    else:
        feedback_parts.append(f"Name mismatch: got '{curr_name}'")

    # 3. Check Short Name at ID (Preferred) vs Global
    curr_short = current.get('short_name', '').strip()
    if curr_short == expected_short:
        score += 25
        feedback_parts.append(f"Short name correctly changed to '{expected_short}'")
    elif global_checks.get('new_short_count', 0) > 0:
        score += 10 # Partial
        feedback_parts.append(f"Short name '{expected_short}' found, but not at original ID")
    else:
        feedback_parts.append(f"Short name mismatch: got '{curr_short}'")

    # 4. Old Name Removed
    if global_checks.get('old_name_count', 0) == 0:
        score += 15
        feedback_parts.append("Old department name no longer exists")
    else:
        feedback_parts.append("Old department name still exists")

    # 5. Associations Intact
    initial_assoc = result.get('initial_assoc_count', 0)
    current_assoc = current.get('assoc_count', 0)
    
    # If initial was 0, this check is trivial pass, otherwise we check if they kept it
    if initial_assoc > 0:
        if current_assoc >= initial_assoc:
            score += 15
            feedback_parts.append(f"User associations preserved ({current_assoc})")
        else:
            feedback_parts.append(f"User associations lost (dropped from {initial_assoc} to {current_assoc})")
    else:
        # If there were no associations to begin with, give points (task limitation)
        score += 15
        feedback_parts.append("No initial associations to preserve")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }