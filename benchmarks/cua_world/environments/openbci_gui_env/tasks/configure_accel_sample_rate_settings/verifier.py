#!/usr/bin/env python3
"""
Verifier for configure_accel_sample_rate_settings@1
Uses VLM to check if the OpenBCI Hardware Settings panel shows 25Hz.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_accel_settings(traj, env_info, task_info):
    """
    Verifies that the OpenBCI GUI Hardware Settings were configured to 25Hz.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Determine which image to verify
    # If agent created the specific file, verify that (bonus points).
    # Otherwise/Additionally, verify the system final state (did they leave it open?).
    
    agent_valid = result_data.get("agent_screenshot_valid", False)
    image_to_check = None
    
    if agent_valid:
        score += 20
        feedback_parts.append("Agent created screenshot successfully (20 pts).")
        # Pull the agent's screenshot
        local_agent_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(result_data["agent_screenshot_path"], local_agent_img)
            image_to_check = local_agent_img
        except:
            feedback_parts.append("Could not retrieve agent screenshot.")
    else:
        feedback_parts.append("Agent did not save screenshot to specified path.")

    # If agent didn't provide a valid screenshot, or even if they did, 
    # we might want to check the final system state if the agent's one is unclear.
    # But sticking to the plan: if agent provided one, check that. 
    # If not, check system final state to see if they did the work but failed the screenshot part.
    if not image_to_check:
        local_sys_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(result_data["system_screenshot_path"], local_sys_img)
            image_to_check = local_sys_img
            feedback_parts.append("Checking final screen state.")
        except:
            return {"passed": False, "score": score, "feedback": "No evidence available."}

    # 3. VLM Verification
    # We ask specifically about the Hardware/Accelerometer settings
    prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    1. Is a "Hardware Settings", "Cyton", "Accelerometer", or "Aux" settings panel/popup visible?
    2. Look for a "Sample Rate" dropdown or setting. Does it show "25Hz" or "25"?
    
    Return JSON:
    {
        "settings_panel_visible": boolean,
        "sample_rate_25hz": boolean,
        "current_value": "string (what you see)"
    }
    """
    
    try:
        vlm_resp = query_vlm(prompt=prompt, image=image_to_check)
        analysis = vlm_resp.get("parsed", {})
        
        # Scoring Logic
        if analysis.get("settings_panel_visible", False):
            score += 40
            feedback_parts.append("Hardware settings panel found (40 pts).")
            
            if analysis.get("sample_rate_25hz", False):
                score += 40
                feedback_parts.append("Sample rate confirmed at 25Hz (40 pts).")
            else:
                val = analysis.get("current_value", "unknown")
                feedback_parts.append(f"Sample rate incorrect. Visible value: {val}.")
        else:
            feedback_parts.append("Hardware settings panel NOT visible in screenshot.")
            
    except Exception as e:
        feedback_parts.append(f"VLM analysis failed: {str(e)}")

    # Cleanup images
    if image_to_check and os.path.exists(image_to_check):
        os.unlink(image_to_check)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }