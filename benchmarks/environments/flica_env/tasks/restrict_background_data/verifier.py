#!/usr/bin/env python3
"""
Verifier for restrict_background_data task.

Task: Disable "Background data" for Flight Crew View.

Verification Strategy:
1. Programmatic (Primary): Check `dumpsys netpolicy` output.
   - If "Background data" is OFF, the policy for the UID should contain 'REJECT_METERED_BACKGROUND' (or similar rejection flag).
   - If "Background data" is ON (default), the policy is typically 'NONE' or lacks the rejection flag.

2. Visual (Secondary): Check final screenshot using VLM.
   - Look for "Background data" toggle in OFF state.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_background_data(traj, env_info, task_info):
    """
    Verify that background data usage is restricted for the app.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    policy_line = result_data.get('policy_line', '')
    uid = result_data.get('uid', '')

    # 2. Programmatic Verification (60 points)
    # Expected policy line format example: "UID=10123 policy=REJECT_METERED_BACKGROUND state=..."
    # The key is seeing a restriction policy. 
    # 'REJECT_METERED_BACKGROUND' is the standard flag for "Background data" toggle OFF.
    
    if uid and uid in policy_line:
        if "REJECT_METERED_BACKGROUND" in policy_line:
            score += 60
            feedback_parts.append("System policy confirms background data restricted")
        elif "policy=NONE" in policy_line:
            feedback_parts.append("System policy shows NO restriction (Default state)")
        else:
            # Fallback for some Android versions or if mixed states
            if "REJECT" in policy_line:
                 score += 60
                 feedback_parts.append("System policy indicates restriction")
            else:
                 feedback_parts.append(f"System policy unclear: {policy_line}")
    else:
        feedback_parts.append("Could not verify system policy (UID mismatch or empty)")

    # 3. VLM Verification (40 points)
    # Use the trajectory final screenshot
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        vlm_prompt = """
        You are verifying settings on an Android phone.
        Task: Turn OFF 'Background data' for an app.
        
        Look at the screenshot and determine:
        1. Are we on an 'App Info' or 'App data usage' / 'Mobile data & Wi-Fi' screen?
        2. Is there a toggle labeled 'Background data' (or 'Enable background usage')?
        3. Is that toggle switched OFF (gray/left) or ON (colored/right)?
        
        Return JSON:
        {
            "is_settings_screen": true/false,
            "background_data_toggle_visible": true/false,
            "toggle_is_off": true/false
        }
        """
        
        vlm_result = query_vlm(image=final_screenshot, prompt=vlm_prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("background_data_toggle_visible") and parsed.get("toggle_is_off"):
                score += 40
                feedback_parts.append("Visual verification: Toggle confirmed OFF")
            elif parsed.get("background_data_toggle_visible") and not parsed.get("toggle_is_off"):
                feedback_parts.append("Visual verification: Toggle appears ON (Fail)")
            elif not parsed.get("is_settings_screen"):
                 # If they are not on the settings screen, we rely entirely on the programmatic check
                 # But we deduct potential points for not showing the work if programmatic failed
                 feedback_parts.append("Visual verification: Not on settings screen")
        else:
            feedback_parts.append("Visual verification failed (VLM error)")
            # If VLM fails but programmatic passed, we grant full remaining points to avoid false negative
            if score == 60: 
                score += 40
                feedback_parts.append("(Auto-granting visual points due to system confirmation)")
    else:
        feedback_parts.append("No screenshot available")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }