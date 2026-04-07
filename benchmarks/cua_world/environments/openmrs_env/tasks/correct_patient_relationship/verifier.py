#!/usr/bin/env python3
"""
Verifier for correct_patient_relationship task.
Checks if the relationship between the two patients was updated from Sibling to Parent.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_relationship(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # 2. Extract Data
    found_parent = result.get('found_parent_rel', False)
    found_sibling = result.get('found_sibling_rel', False)
    correct_direction = result.get('is_correct_direction', False)

    score = 0
    feedback = []

    # 3. Verify Criteria
    
    # Criterion A: Old Sibling relationship removed/voided (30 pts)
    if not found_sibling:
        score += 30
        feedback.append("Old 'Sibling' relationship successfully removed.")
    else:
        feedback.append("The incorrect 'Sibling' relationship is still active.")

    # Criterion B: New Parent relationship exists (30 pts)
    if found_parent:
        score += 30
        feedback.append("New 'Parent' relationship found.")
    else:
        feedback.append("No 'Parent' relationship found between the patients.")

    # Criterion C: Directionality (40 pts)
    # Critical: A Parent relationship implies hierarchy. 
    # If reversed (Child is Parent of Mother), it's factually wrong in the EHR.
    if found_parent and correct_direction:
        score += 40
        feedback.append("Relationship direction is correct (Martha is Parent).")
    elif found_parent and not correct_direction:
        feedback.append("Relationship direction is REVERSED (Child marked as Parent).")
    
    # 4. Anti-Gaming Check (implied by database state check)
    # The setup script specifically creates the wrong state. 
    # If the right state exists, the agent must have acted.

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }