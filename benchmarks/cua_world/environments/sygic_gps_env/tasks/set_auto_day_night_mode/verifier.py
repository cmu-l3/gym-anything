#!/usr/bin/env python3
"""
Verifier for set_auto_day_night_mode task.

Verification Strategy:
1. Anti-gaming: Check if task duration was reasonable (>5s) and app is running.
2. VLM Analysis:
   - Use trajectory frames to verify the user navigated to Settings.
   - Use final screenshot (and trajectory) to verify "Automatic" mode is selected.
   - We do NOT rely solely on the final screenshot to prevent "already set" gaming,
     though the setup script tries to ensure a clean state.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_auto_day_night_mode(traj, env_info, task_info):
    """
    Verifies that the agent set the map color scheme to Automatic using VLM.
    """
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Basic Checks (Anti-gaming) - 20 Points
    score = 0
    feedback_log = []
    
    # Check 1: App Running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_log.append("App is running.")
    else:
        feedback_log.append("App was closed (fail).")
        return {"passed": False, "score": 0, "feedback": "App was not running at the end of the task."}

    # Check 2: Task Duration (10 pts)
    start_time = result_data.get("task_start", 0)
    end_time = result_data.get("task_end", 0)
    duration = end_time - start_time
    if duration > 5:
        score += 10
        feedback_log.append(f"Task duration valid ({duration}s).")
    else:
        feedback_log.append(f"Task too short ({duration}s).")
        return {"passed": False, "score": 10, "feedback": "Task completed too quickly to be valid."}

    # 3. VLM Verification - 80 Points
    # We select frames from the trajectory to see the steps, plus the final state.
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not trajectory_frames and not final_frame:
         return {"passed": False, "score": score, "feedback": "No video evidence available."}
    
    analysis_images = trajectory_frames + [final_frame] if final_frame else trajectory_frames

    prompt = """
    You are verifying an Android navigation app task. The goal is to set the Map Color Scheme to 'Automatic'.
    
    Review the sequence of screenshots.
    1. Did the user open the main menu (hamburger icon) and go to 'Settings'?
    2. Did the user navigate to 'Map', 'Display', or 'View & Units' settings?
    3. Did the user locate a 'Color scheme' or 'Day/Night mode' setting?
    4. CRITICAL: Is the setting currently set to 'Automatic', 'Auto', or 'Switch automatically'?
       (Look for a checkmark, radio button, or text indicating 'Automatic' is active).
    
    Return a JSON object with:
    {
        "opened_settings": true/false,
        "found_color_setting": true/false,
        "selected_automatic": true/false,
        "final_state_is_automatic": true/false,
        "reasoning": "your observation"
    }
    """
    
    try:
        vlm_response = query_vlm(images=analysis_images, prompt=prompt)
        parsed = vlm_response.get("parsed", {})
        
        # Scoring logic based on VLM
        if parsed.get("opened_settings"):
            score += 20
            feedback_log.append("Agent opened Settings.")
        else:
            feedback_log.append("Failed to find Settings.")

        if parsed.get("found_color_setting"):
            score += 20
            feedback_log.append("Agent located Color/Display settings.")
        else:
            feedback_log.append("Failed to locate Color/Display settings.")

        # The critical success criteria
        if parsed.get("selected_automatic") or parsed.get("final_state_is_automatic"):
            score += 40
            feedback_log.append("Automatic mode verified.")
        else:
            feedback_log.append("Automatic mode NOT verified in final state.")

    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_log.append("Verification error during visual analysis.")
        # Fallback: if we passed basic checks, give minimal score
        return {"passed": False, "score": score, "feedback": "VLM analysis failed: " + str(e)}

    # Final Pass/Fail
    passed = score >= 80  # Requires App Running (10) + Duration (10) + Settings (20) + Found (20) + Auto (40) = 100.
                          # Allow some wiggle room if intermediate steps missed but result perfect? 
                          # Let's say Threshold 70.
    passed = score >= 70 and (parsed.get("selected_automatic") or parsed.get("final_state_is_automatic"))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log),
        "details": parsed
    }