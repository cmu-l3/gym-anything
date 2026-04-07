#!/usr/bin/env python3
"""
Verifier for configure_ganglion_4ch_synthetic task.
Verifies that the agent correctly switched to Ganglion board (4 channels)
and captured the requested screenshot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ganglion_4ch_synthetic(traj, env_info, task_info):
    """
    Verification Logic:
    1. Check if user-generated screenshot exists and is valid (timestamp check).
    2. VLM Check 1: Analyze user screenshot to confirm 4 channels (Ganglion) vs 8 channels (Cyton).
    3. VLM Check 2: Analyze final system screenshot to confirm active session.
    4. VLM Check 3: Analyze trajectory to confirm settings change.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Basic Criteria
    user_screenshot_exists = result_data.get("user_screenshot_exists", False)
    timestamp_valid = result_data.get("user_screenshot_valid_timestamp", False)
    app_running = result_data.get("app_running", False)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: User screenshot file validity (20 pts)
    if user_screenshot_exists and timestamp_valid:
        score += 20
        feedback_parts.append("User screenshot created successfully.")
    elif user_screenshot_exists:
        score += 5
        feedback_parts.append("User screenshot exists but has invalid timestamp (pre-existing file?).")
    else:
        feedback_parts.append("User screenshot not found.")

    # 3. VLM Verification
    
    # Get user screenshot from container for VLM analysis
    user_screenshot_local = None
    if user_screenshot_exists:
        try:
            remote_path = result_data.get("user_screenshot_path")
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(remote_path, temp_img.name)
            user_screenshot_local = temp_img.name
        except Exception as e:
            logger.error(f"Failed to copy user screenshot: {e}")

    # Prompt for User Screenshot Analysis
    # We specifically look for "4 channels" which indicates Ganglion mode.
    # Cyton (default) has 8 channels.
    user_ss_prompt = """
    Analyze this OpenBCI GUI screenshot.
    1. Count the number of EEG channels visible in the Time Series widget (the waveform graphs).
    2. Are there exactly 4 channels active/visible? (Ganglion board has 4, Cyton has 8).
    3. Does the data look like streaming EEG/waves (not flat lines)?
    
    Return JSON: {"channel_count": int, "is_4_channels": bool, "is_streaming": bool}
    """
    
    vlm_score_user = 0
    if user_screenshot_local:
        try:
            vlm_res = query_vlm(user_ss_prompt, images=[user_screenshot_local])
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("is_4_channels"):
                vlm_score_user += 40
                feedback_parts.append("VLM confirms 4 channels visible (Ganglion mode).")
            else:
                cnt = parsed.get("channel_count", "unknown")
                feedback_parts.append(f"VLM saw {cnt} channels (expected 4).")
                
            if parsed.get("is_streaming"):
                vlm_score_user += 10
                feedback_parts.append("VLM confirms data is streaming.")
            else:
                feedback_parts.append("VLM indicates data might not be streaming.")
        except Exception as e:
            feedback_parts.append(f"VLM analysis of user screenshot failed: {e}")
        finally:
            if user_screenshot_local and os.path.exists(user_screenshot_local):
                os.unlink(user_screenshot_local)
    
    score += vlm_score_user

    # Trajectory Analysis (30 pts)
    # Check if they actually went to the settings and changed the board
    traj_frames = sample_trajectory_frames(traj, n=4)
    if not traj_frames:
        feedback_parts.append("No trajectory frames available.")
    else:
        traj_prompt = """
        Review these screenshots of the user's workflow in OpenBCI GUI.
        Did the user:
        1. Navigate to the System Control Panel (start screen)?
        2. Interact with the 'DATA SOURCE' or 'Board' dropdown menu?
        3. Select 'Ganglion' or change the board type?
        4. Start a session?
        
        Return JSON: {"changed_board": bool, "started_session": bool}
        """
        try:
            vlm_res_traj = query_vlm(traj_prompt, images=traj_frames)
            parsed_traj = vlm_res_traj.get("parsed", {})
            
            if parsed_traj.get("changed_board"):
                score += 15
                feedback_parts.append("Trajectory shows board configuration change.")
            else:
                feedback_parts.append("Trajectory does not clearly show board change.")
                
            if parsed_traj.get("started_session"):
                score += 15
                feedback_parts.append("Trajectory shows session start.")
        except Exception as e:
            feedback_parts.append(f"Trajectory analysis failed: {e}")

    # Final Score Calculation
    passed = score >= 60 and (vlm_score_user >= 30) # Require visual confirmation of 4 channels
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }