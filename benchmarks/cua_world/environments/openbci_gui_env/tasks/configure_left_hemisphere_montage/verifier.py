#!/usr/bin/env python3
"""
Verifier for configure_left_hemisphere_montage task.

Verifies:
1. OpenBCI GUI is running.
2. User saved a screenshot to the correct path.
3. VLM Analysis of the user's screenshot AND the final system state:
   - Playback mode active (wobbly lines).
   - Only 4 channels visible.
   - Visible channels are 1, 3, 5, 7 (Odd/Left).
   - Time window is ~10 seconds.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_left_hemisphere_montage(traj, env_info, task_info):
    """
    Verify the left hemisphere montage configuration.
    """
    # 1. Setup and retrieve data using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    user_screenshot_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # Copy JSON result
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
            
        # Copy user screenshot if it exists
        user_screenshot_path = result_data.get("user_screenshot_path")
        has_user_screenshot = False
        if result_data.get("user_screenshot_exists") and user_screenshot_path:
            try:
                copy_from_env(user_screenshot_path, user_screenshot_file.name)
                has_user_screenshot = True
            except Exception as e:
                logger.warning(f"Could not copy user screenshot: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)
        # We keep user_screenshot_file for VLM if needed, verify cleanup later

    # 2. Score Calculation
    score = 0
    feedback = []

    # Criterion A: Application Running (10 pts)
    if result_data.get("app_was_running"):
        score += 10
        feedback.append("OpenBCI GUI was running.")
    else:
        feedback.append("OpenBCI GUI was NOT running at end of task.")

    # Criterion B: Screenshot File Evidence (20 pts)
    if result_data.get("user_screenshot_exists"):
        if result_data.get("user_screenshot_valid_time"):
            score += 20
            feedback.append("User screenshot saved correctly.")
        else:
            score += 10
            feedback.append("User screenshot exists but timestamp is suspicious (pre-existing?).")
    else:
        feedback.append("User screenshot NOT found at expected path.")

    # Criterion C: VLM Verification (70 pts)
    # We analyze the user's screenshot (if available) OR the final system state as fallback.
    # If user screenshot exists, we weight it higher as it proves the "take screenshot" action.
    
    image_to_analyze = None
    if has_user_screenshot:
        image_to_analyze = user_screenshot_file.name
        source_desc = "user's saved screenshot"
    else:
        # Fallback to final frame from trajectory if user didn't save file
        image_to_analyze = get_final_screenshot(traj)
        source_desc = "final screen state"

    if image_to_analyze:
        vlm_prompt = (
            "Analyze this OpenBCI GUI screen. "
            "1. Are the even-numbered channels (2, 4, 6, 8) turned OFF/HIDDEN? "
            "2. Are the odd-numbered channels (1, 3, 5, 7) turned ON/VISIBLE? "
            "3. Look at the Time Series widget x-axis or settings: Is the window duration set to approximately 10 seconds? "
            "4. Is data actively streaming (lines look like wavy EEG signals, not flat lines)? "
            "Respond in JSON: {\"only_odd_channels_visible\": bool, \"window_is_10s\": bool, \"active_streaming\": bool}"
        )
        
        vlm_response = query_vlm(vlm_prompt, image_to_analyze)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            # Sub-score: Channels correct (30 pts)
            if parsed.get("only_odd_channels_visible", False):
                score += 30
                feedback.append(f"VLM confirmed only odd channels (Left Hemisphere) visible in {source_desc}.")
            else:
                feedback.append(f"VLM did NOT see correct channel isolation in {source_desc}.")
                
            # Sub-score: Window 10s (20 pts)
            if parsed.get("window_is_10s", False):
                score += 20
                feedback.append(f"VLM confirmed 10s time window in {source_desc}.")
            else:
                feedback.append(f"VLM did NOT confirm 10s time window in {source_desc}.")
                
            # Sub-score: Active Streaming (20 pts)
            if parsed.get("active_streaming", False):
                score += 20
                feedback.append("VLM confirmed active data streaming.")
            else:
                feedback.append("VLM did not detect active streaming (flat lines or static).")
        else:
            feedback.append("VLM analysis failed.")
            # Fallback scoring if VLM fails technically? No, strict verification.
    else:
        feedback.append("No image available for VLM verification.")

    # Cleanup
    if os.path.exists(user_screenshot_file.name):
        os.unlink(user_screenshot_file.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }