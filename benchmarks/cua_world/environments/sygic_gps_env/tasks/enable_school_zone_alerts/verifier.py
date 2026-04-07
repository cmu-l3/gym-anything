#!/usr/bin/env python3
"""
Verifier for enable_school_zone_alerts task.

Verification Strategy:
1. VLM Analysis of Trajectory:
   - Verify navigation to Settings > Notifications/Safety.
   - Verify identification of "School Zone" option.
2. VLM Analysis of Final State:
   - Confirm "School Zone" toggle is visibly ON.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_school_zone_alerts(traj, env_info, task_info):
    """
    Verify that the agent enabled School Zone alerts using VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve metadata and result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result_data.get("app_was_running", False):
        return {"passed": False, "score": 0, "feedback": "Sygic app was not running at the end of the task."}

    # 2. Prepare VLM Query
    # We use trajectory frames to ensure they actually navigated the menu
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
         return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}

    # Combine frames for context, but focus analysis on finding the specific setting
    images_to_analyze = frames + [final_screenshot]

    prompt = """
    You are verifying an Android navigation task. 
    The goal is to enable "School Zone" safety alerts in Sygic GPS Navigation.

    Please analyze the screenshots to answer the following:
    1. Did the user navigate to a "Settings" menu?
    2. Did the user enter a "Notifications", "Sounds", or "Safety" submenu?
    3. Is the "School Zone" (or similar, like "School") setting visible in any screenshot?
    4. In the FINAL screenshot, is the "School Zone" toggle/checkbox switched ON (enabled)?
       (Look for colored toggles, checkmarks, or standard Android 'on' switches).

    Return your assessment in JSON format:
    {
        "settings_opened": boolean,
        "notifications_submenu_opened": boolean,
        "school_zone_option_visible": boolean,
        "school_zone_enabled_final": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """

    # 3. Query VLM
    try:
        vlm_response = query_vlm(images=images_to_analyze, prompt=prompt)
        assessment = vlm_response.get('parsed', {})
    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        return {"passed": False, "score": 0, "feedback": "Verification failed due to VLM error."}

    # 4. Calculate Score
    score = 0
    feedback_parts = []

    if assessment.get("settings_opened"):
        score += 10
        feedback_parts.append("Opened Settings")
    
    if assessment.get("notifications_submenu_opened"):
        score += 20
        feedback_parts.append("Entered Notifications/Safety menu")

    if assessment.get("school_zone_option_visible"):
        score += 30
        feedback_parts.append("Found School Zone option")

    if assessment.get("school_zone_enabled_final"):
        score += 40
        feedback_parts.append("School Zone alert confirmed ON")
    else:
        feedback_parts.append("School Zone alert NOT confirmed ON in final state")

    # Pass logic: Must find the option and have it enabled
    passed = score >= 90  # Strict pass: must do almost everything right
    
    # If confidence is low, penalize or fail
    if assessment.get("confidence") == "low":
        feedback_parts.append("(Low verification confidence)")
        # If we think it passed but confidence is low, maybe manually review? 
        # For auto-grading, we might keep the score but flag it. 
        # Here we accept it but note it.

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts),
        "details": assessment
    }