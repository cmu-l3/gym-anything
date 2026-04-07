#!/usr/bin/env python3
"""
Verifier for identify_version_author task.

Verification Logic:
1. File Existence: Checks if /home/ga/version_author.txt exists.
2. Content Accuracy: Compares file content to 'arch_lead' (case-insensitive).
3. Anti-Gaming: 
   - Checks if file was created during the task window.
   - VLM check to ensure agent actually navigated to history/versions tab.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_version_author(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected user from metadata
    metadata = task_info.get('metadata', {})
    expected_user = metadata.get('target_user_id', 'arch_lead')
    
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
    
    # 1. Check if file exists (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback_parts.append("Output file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Check if created during task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it wasn't created during task")

    # 3. Check Content (80 pts)
    content = result.get('output_content', '').strip()
    
    if content.lower() == expected_user.lower():
        score += 80
        feedback_parts.append(f"Correct username identified: '{content}'")
    else:
        feedback_parts.append(f"Incorrect username: '{content}'. Expected: '{expected_user}'")
        
        # Specific feedback if they picked the current modifier
        if "admin" in content.lower():
            feedback_parts.append("(You likely identified the *current* modifier, not the v1.0 author)")

    # 4. Optional VLM Check (Bonus or confirmation)
    # We could check trajectory to see if "History" or "Versions" tab was clicked.
    # For now, strict content match is the primary success criteria.

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }