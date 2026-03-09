#!/usr/bin/env python3
"""
Verifier for create_encounter_role task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_encounter_role(traj, env_info, task_info):
    """
    Verify that the 'Scrub Nurse' encounter role was created correctly.
    
    Criteria:
    1. Role exists in the system (found via API).
    2. Name matches 'Scrub Nurse' exactly.
    3. Description contains required keywords (nurse, surgical, instruments).
    4. Encounter role count increased (anti-gaming: verifies creation happened now).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Scrub Nurse")
    keywords = metadata.get('expected_description_keywords', ["nurse", "surgical", "instruments"])

    # Load result from container
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
    
    # Data from result
    found_role = result.get('found_role')
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))

    # Criterion 1: Role Exists (30 pts)
    if found_role:
        score += 30
        feedback.append("Role found in system.")
        
        # Criterion 2: Name Exact Match (30 pts)
        actual_name = found_role.get('name', '').strip()
        if actual_name == expected_name:
            score += 30
            feedback.append(f"Name matches exactly ('{actual_name}').")
        elif actual_name.lower() == expected_name.lower():
            score += 15
            feedback.append(f"Name matches case-insensitive ('{actual_name}').")
        else:
            feedback.append(f"Name mismatch: Expected '{expected_name}', got '{actual_name}'.")

        # Criterion 3: Description Keywords (25 pts)
        description = found_role.get('description', '').lower()
        found_keywords = [kw for kw in keywords if kw in description]
        if len(found_keywords) == len(keywords):
            score += 25
            feedback.append("Description contains all required keywords.")
        elif found_keywords:
            partial = int(25 * (len(found_keywords) / len(keywords)))
            score += partial
            feedback.append(f"Description missing some keywords. Found: {found_keywords}.")
        else:
            feedback.append("Description missing required keywords.")

    else:
        feedback.append("Role 'Scrub Nurse' not found in system.")

    # Criterion 4: Anti-gaming / Count Increase (15 pts)
    if current_count > initial_count:
        score += 15
        feedback.append("New role count increased.")
    elif found_role:
        # If role found but count didn't increase, maybe it wasn't purged correctly or reused?
        feedback.append("Warning: Role count did not increase.")
    
    passed = score >= 85  # Requires role found + correct name + most description
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }