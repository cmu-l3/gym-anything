#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bias_exclusion(traj, env_info, task_info):
    """
    Verifies that the agent correctly configured the Hardware Settings:
    - Channels 7 & 8 Bias = OFF
    - Channels 1-6 Bias = ON
    - Hardware Settings panel is visible
    """
    
    # 1. Setup and Copy Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    # Load the JSON result exported from the container
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

    score = 0
    feedback_parts = []
    
    # 2. Basic Process & File Checks (30 points total)
    
    # Check if app was running (10 pts)
    if result_data.get("app_running", False):
        score += 10
    else:
        feedback_parts.append("OpenBCI GUI was closed.")

    # Check if user saved the specific screenshot requested (20 pts)
    # The task asks to save to ~/Documents/OpenBCI_GUI/Screenshots/bias_config.png
    user_screenshot_valid = result_data.get("user_screenshot_valid_time", False)
    if user_screenshot_valid:
        score += 20
        feedback_parts.append("Proof screenshot saved correctly.")
    elif result_data.get("user_screenshot_exists", False):
        # Exists but wrong timestamp (pre-existing?)
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is suspicious.")
    else:
        feedback_parts.append("Required screenshot 'bias_config.png' not found.")

    # 3. VLM Verification (70 points total)
    # We analyze the FINAL screenshot captured by the system (more reliable than user file)
    # and potentially the user's file if available.
    
    final_frame = get_final_screenshot(traj)
    # Optionally sample trajectory to see if they opened the menu
    traj_frames = sample_trajectory_frames(traj, n=3)
    
    prompt = """
    You are evaluating an agent's configuration of the OpenBCI GUI Hardware Settings.
    
    The goal is:
    1. The "Hardware Settings" panel must be OPEN (a grid of buttons for each channel).
    2. In the "Bias" column (sometimes labeled "Include" or "Bias"), specific channels must be excluded.
    3. Channels 7 and 8 must be set to OFF (unchecked/greyed out) in the Bias column.
    4. Channels 1 through 6 must remain ON (checked/colored) in the Bias column.
    
    Look at the provided screenshot.
    
    Q1: Is the Hardware Settings panel visible?
    Q2: Is the Bias column visible?
    Q3: Are Channels 7 and 8 disabled/OFF in the Bias column?
    Q4: Are Channels 1-6 enabled/ON in the Bias column?
    
    Output JSON:
    {
        "panel_visible": boolean,
        "bias_column_found": boolean,
        "ch7_8_off": boolean,
        "ch1_6_on": boolean,
        "reasoning": "string explanation"
    }
    """
    
    vlm_response = query_vlm(
        images=[final_frame], 
        prompt=prompt
    )
    
    analysis = vlm_response.get("parsed", {})
    
    # Scoring VLM output
    if analysis.get("panel_visible", False):
        score += 20
        
        if analysis.get("bias_column_found", False):
            # Detailed settings check
            if analysis.get("ch7_8_off", False):
                score += 30
                feedback_parts.append("Channels 7 & 8 correctly excluded from Bias.")
            else:
                feedback_parts.append("Channels 7 & 8 appear to still be included in Bias (Fail).")
                
            if analysis.get("ch1_6_on", False):
                score += 20
                feedback_parts.append("Channels 1-6 correctly preserved.")
            else:
                feedback_parts.append("Channels 1-6 were incorrectly modified.")
        else:
            feedback_parts.append("Hardware panel open, but Bias column not identified.")
    else:
        feedback_parts.append("Hardware Settings panel is not visible in the final state.")

    # Final Evaluation
    passed = score >= 90  # Strict pass: Must have app running + screenshot + correct config
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }