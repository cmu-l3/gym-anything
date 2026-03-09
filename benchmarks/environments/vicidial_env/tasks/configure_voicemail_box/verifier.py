#!/usr/bin/env python3
"""
Verifier for configure_voicemail_box task.
Checks if the voicemail box was created in the database with the correct settings.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_voicemail_box(traj, env_info, task_info):
    """
    Verify voicemail box configuration.
    
    Criteria:
    1. Record exists (30 pts)
    2. Email matches (20 pts)
    3. Delete After Email is Y (25 pts)
    4. Active is Y (10 pts)
    5. Timezone is correct (10 pts)
    6. Name/Pass match (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('expected_id', '8500')
    expected_email = metadata.get('expected_email', 'tickets@westcoast-support.com')
    expected_delete = metadata.get('expected_delete', 'Y')
    expected_zone = metadata.get('expected_zone', 'America/Los_Angeles')
    
    # Load result JSON
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
    
    # Check 1: Record Existence
    if not result.get('record_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Voicemail box {expected_id} was not created."
        }
    
    score += 30
    feedback_parts.append("Voicemail box created")
    
    # Check 2: Email
    actual_email = result.get('email', '')
    if actual_email == expected_email:
        score += 20
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append(f"Email mismatch: expected {expected_email}, got {actual_email}")
        
    # Check 3: Delete Policy (Critical)
    actual_delete = result.get('delete_vm_after_email', 'N')
    if actual_delete == expected_delete:
        score += 25
        feedback_parts.append("Delete policy correct")
    else:
        feedback_parts.append(f"Delete policy mismatch: expected {expected_delete}, got {actual_delete}")
        
    # Check 4: Active Status
    actual_active = result.get('active', 'N')
    if actual_active == 'Y':
        score += 10
        feedback_parts.append("Active status correct")
    else:
        feedback_parts.append("Voicemail box is not active")
        
    # Check 5: Timezone
    actual_zone = result.get('zone', '')
    # Allow loose matching if timezone names vary slightly, but Vicidial usually uses specific strings
    if expected_zone in actual_zone or actual_zone in expected_zone:
        score += 10
        feedback_parts.append("Timezone correct")
    else:
        feedback_parts.append(f"Timezone mismatch: expected {expected_zone}, got {actual_zone}")
        
    # Check 6: Name and Password
    actual_name = result.get('fullname', '')
    actual_pass = result.get('password', '')
    if actual_name == metadata.get('expected_name') and actual_pass == metadata.get('expected_pass'):
        score += 5
        feedback_parts.append("Name/Pass correct")
    else:
        feedback_parts.append("Name or Password mismatch")

    # VLM Verification (Bonus/Anti-gaming)
    # Ensure they actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        if frames:
            vlm_prompt = "Does the user appear to be interacting with a voicemail or admin configuration form in a web browser?"
            vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                # We don't deduct points usually, but we could use this for debugging
                pass
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }