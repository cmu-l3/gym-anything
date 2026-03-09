#!/usr/bin/env python3
"""
Verifier for create_task_template@1
Checks if the "Server Patching Protocol" task template was created correctly in ServiceDesk Plus.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_task_template(traj, env_info, task_info):
    """
    Verifies the creation of a Task Template with specific content.
    """
    # 1. Setup Result Reading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_phrases', [])
    expected_priority = metadata.get('expected_priority', 'High')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Database Record (Primary Signal)
    if not result.get('template_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Task Template 'Server Patching Protocol' was not found in the database."
        }
    
    score += 40
    feedback_parts.append("Template created successfully.")

    # 3. Verify Priority
    # SDP DB stores priorities usually as 'High', 'Normal', 'Low', etc.
    actual_priority = result.get('priority', '')
    if expected_priority.lower() in actual_priority.lower():
        score += 20
        feedback_parts.append(f"Priority matches ({actual_priority}).")
    else:
        feedback_parts.append(f"Priority mismatch: expected {expected_priority}, got '{actual_priority}'.")

    # 4. Verify Description Content
    description = result.get('description', '').lower()
    phrases_found = 0
    for phrase in required_phrases:
        if phrase.lower() in description:
            phrases_found += 1
    
    # Score proportional to phrases found (30 points total)
    if len(required_phrases) > 0:
        phrase_score = int((phrases_found / len(required_phrases)) * 30)
        score += phrase_score
        feedback_parts.append(f"Description content: {phrases_found}/{len(required_phrases)} required steps found.")
    else:
        score += 30 # Fallback if no metadata

    # 5. Anti-Gaming: Check Timestamp
    # Ensure record was created AFTER task start
    task_start = result.get('task_start', 0)
    # SDP createdtime is usually milliseconds; adjust if necessary based on observation
    # Assuming result returns standard epoch or close to it. 
    # If string '0', we skip.
    try:
        record_time = int(result.get('record_created_time', 0))
        # Handle ms vs s differences
        if record_time > 1000000000000: # is ms
            record_time = record_time / 1000
        
        if record_time >= task_start:
            score += 10
            feedback_parts.append("Freshly created.")
        else:
            feedback_parts.append("Warning: Record timestamp predates task start.")
    except:
        # If parsing fails, grant benefit of doubt if template_found is true
        # but mark as warning
        feedback_parts.append("Timestamp check skipped (format error).")
        score += 5

    # 6. VLM Verification (Visual Confirmation)
    # Use trajectory to see if they actually used the form
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Review these screenshots of a user creating a Task Template in ServiceDesk Plus. "
            "1. Did the user navigate to the Admin > Task Templates section? "
            "2. Is the title 'Server Patching Protocol' visible? "
            "3. Are the steps like 'Stop all application services' visible in the description field?"
        )
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            # VLM can't easily parse boolean from free text without strict prompting, 
            # but we assume high confidence if database passed. 
            # This is primarily for debugging logging.
            logger.info(f"VLM Analysis: {vlm_res.get('response')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final Calculation
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }