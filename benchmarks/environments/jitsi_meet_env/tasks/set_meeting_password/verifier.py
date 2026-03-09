#!/usr/bin/env python3
"""
Verifier for set_meeting_password task.

Verification Strategy:
1. Programmatic: Check password extracted from Jitsi internal state via browser JS.
2. VLM: Check final screenshot for Security Options panel and lock icon.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_meeting_password(traj, env_info, task_info):
    """
    Verifies that the Jitsi meeting password was set correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_password = metadata.get('expected_password', 'FlowState24')
    
    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    detected_password = result_data.get('detected_password', '')
    task_start = result_data.get('task_start', 0)
    task_end = result_data.get('task_end', 0)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Password set correctly (Primary, 50 points)
    pass_match = False
    if detected_password == expected_password:
        score += 50
        pass_match = True
        feedback_parts.append(f"Success: Password set to '{expected_password}'")
    elif detected_password == "NULL":
        feedback_parts.append("Fail: No password is set on the room.")
    elif detected_password == "ERROR":
        feedback_parts.append("Fail: Could not read room state (agent might not be in room).")
    else:
        feedback_parts.append(f"Fail: Password set to '{detected_password}', expected '{expected_password}'.")

    # Criterion 2: Anti-gaming (Time check) (10 points)
    duration = task_end - task_start
    if duration > 5:
        score += 10
        feedback_parts.append("Time valid.")
    else:
        feedback_parts.append("Suspiciously fast completion.")

    # Criterion 3: VLM Visual Verification (40 points)
    # We look for the Security Options dialog and the lock icon
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        You are verifying a Jitsi Meet task. The user should have set a password.
        Look at this screenshot and answer:
        1. Is the "Security options" dialog/panel visible? (It usually has a 'Add password' field)
        2. Is there a lock/shield icon in the bottom toolbar or top header indicating the room is secure?
        3. Is the password 'FlowState24' visible in any text field?
        
        Return JSON:
        {
            "security_panel_visible": boolean,
            "lock_icon_visible": boolean,
            "password_text_visible": boolean
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("security_panel_visible"):
                vlm_score += 15
                feedback_parts.append("Visual: Security panel open.")
            
            if parsed.get("lock_icon_visible"):
                vlm_score += 15
                feedback_parts.append("Visual: Lock icon visible.")
                
            if parsed.get("password_text_visible"):
                vlm_score += 10
                feedback_parts.append("Visual: Password text visible.")
        else:
            feedback_parts.append("VLM analysis failed.")
    
    score += vlm_score

    # Final Pass Logic
    # Must have the correct password programmatically AND reasonable visual evidence OR perfect programmatic match
    passed = (pass_match and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }