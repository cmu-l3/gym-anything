#!/usr/bin/env python3
"""
Verifier for process_applicant_phone_screen task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_applicant_phone_screen(traj, env_info, task_info):
    """
    Verifies that the applicant 'Alex Morgan' was correctly processed.
    Criteria:
    1. Stage moved to "First Interview" (40 pts)
    2. Tag "High Potential" added (30 pts)
    3. Note logged in chatter containing key phrases (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_stage = metadata.get('target_stage', 'First Interview')
    target_tag = metadata.get('target_tag', 'High Potential')
    required_note_content = metadata.get('required_note_content', 'passed phone screening')

    # Copy result file
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

    odoo_data = result.get('odoo_data', {})
    
    if not odoo_data.get('applicant_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Applicant 'Alex Morgan' not found in database. Did you delete the record?"
        }

    score = 0
    feedback = []

    # 1. Verify Stage (40 pts)
    actual_stage = odoo_data.get('stage_name', 'Unknown')
    if actual_stage == target_stage:
        score += 40
        feedback.append(f"Correctly moved to stage '{target_stage}'.")
    else:
        feedback.append(f"Incorrect stage: '{actual_stage}' (Expected: '{target_stage}').")

    # 2. Verify Tag (30 pts)
    actual_tags = odoo_data.get('tags', [])
    if target_tag in actual_tags:
        score += 30
        feedback.append(f"Tag '{target_tag}' applied.")
    else:
        feedback.append(f"Missing tag '{target_tag}'. Found: {actual_tags}.")

    # 3. Verify Note (30 pts)
    messages = odoo_data.get('messages', [])
    note_found = False
    for msg in messages:
        # Body is usually HTML, so we do a simple substring check
        if required_note_content.lower() in msg.get('body', '').lower():
            note_found = True
            break
    
    if note_found:
        score += 30
        feedback.append("Chatter note logged successfully.")
    else:
        feedback.append(f"No note found containing '{required_note_content}'.")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }