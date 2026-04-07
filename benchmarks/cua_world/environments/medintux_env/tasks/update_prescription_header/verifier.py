#!/usr/bin/env python3
"""
Verifier for update_prescription_header task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_prescription_header(traj, env_info, task_info):
    """
    Verify the prescription header update.
    
    Criteria:
    1. Template file exists (10 pts)
    2. File was modified during task (timestamp check) (20 pts)
    3. New Street Address present (30 pts)
    4. New City/Zip present (20 pts)
    5. New Phone present (10 pts)
    6. Old Address removed (10 pts)
    
    Pass threshold: 70 points AND New Address must be present.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback = []

    # Criterion 1: File Exists
    if result.get("file_exists", False):
        score += 10
        feedback.append("Template file found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Template file deleted or not found."}

    # Criterion 2: Modification Timestamp (Anti-Gaming)
    if result.get("file_modified", False):
        score += 20
        feedback.append("Template was updated.")
    else:
        feedback.append("Template file timestamp not updated (did you save?).")

    # Criterion 3: New Street Address (Critical)
    if result.get("content_match_address", False):
        score += 30
        feedback.append("Street address updated correctly.")
    else:
        feedback.append("New street address not found.")

    # Criterion 4: New City
    if result.get("content_match_city", False):
        score += 20
        feedback.append("City/Zip updated.")
    else:
        feedback.append("City/Zip not found.")
        
    # Criterion 5: New Phone
    if result.get("content_match_phone", False):
        score += 10
        feedback.append("Phone number updated.")
    else:
        feedback.append("Phone number not found.")

    # Criterion 6: Old Info Removed
    if result.get("content_removed_old", False):
        score += 10
        feedback.append("Old address successfully removed.")
    else:
        feedback.append("Old address still present in file.")

    # Pass logic
    # Must have updated the file AND included the street address at minimum
    passed = (score >= 70) and result.get("content_match_address", False) and result.get("file_modified", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }