#!/usr/bin/env python3
"""
Verifier for configure_dual_band_power_asymmetry task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dual_band_power_asymmetry(traj, env_info, task_info):
    """
    Verify that the agent configured two Band Power widgets for asymmetry analysis.
    
    Criteria:
    1. User screenshot file exists and was created during task (10 pts).
    2. VLM Verification (90 pts total):
       - Session is active/playback running (20 pts).
       - Two Band Power widgets are visible (30 pts).
       - Widget 1 shows primarily Channel 1 (Grey/Dark) (20 pts).
       - Widget 2 shows primarily Channel 2 (Purple) (20 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load execution results
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
    
    # --- Check 1: File Existence (10 pts) ---
    if result.get('user_screenshot_exists') and result.get('user_screenshot_created_during_task'):
        score += 10
        feedback_parts.append("User screenshot saved correctly (+10)")
    elif result.get('user_screenshot_exists'):
        score += 5
        feedback_parts.append("User screenshot exists but timestamp is old (+5)")
    else:
        feedback_parts.append("User screenshot not found (0)")

    # --- Check 2: VLM Verification (90 pts) ---
    # Use the final frame from trajectory or the system screenshot captured by export script
    # We prefer the system screenshot captured in export_result.sh if accessible, 
    # but framework trajectory is more standard.
    
    final_image = get_final_screenshot(traj)
    
    if final_image is None:
        return {"passed": False, "score": score, "feedback": "No visual evidence available for VLM."}

    prompt = """
    You are verifying an OpenBCI GUI task. The user was supposed to:
    1. Be playing back an EEG recording (look for "Stop Data Stream" button or active graphs).
    2. Have TWO "Band Power" widgets side-by-side or visible on the dashboard.
    3. Configure the first widget to show ONLY Channel 1 (Look for Grey/Black bars).
    4. Configure the second widget to show ONLY Channel 2 (Look for Purple bars).
    
    Analyze the image:
    - Is the session active (data streaming)?
    - Are there exactly two Band Power widgets? (They look like bar charts with Delta/Theta/Alpha/Beta/Gamma labels).
    - Does one widget show bars of a single color (Grey)?
    - Does the other widget show bars of a single color (Purple)?
    - If they show multi-colored bars, the channel isolation failed.
    
    Return JSON:
    {
        "session_active": boolean,
        "two_band_power_widgets_visible": boolean,
        "widget_1_channel_1_isolated": boolean,
        "widget_2_channel_2_isolated": boolean,
        "explanation": "string"
    }
    """
    
    vlm_response = query_vlm(
        images=[final_image], 
        prompt=prompt,
        format_type="json"
    )
    
    if not vlm_response.get("success"):
        feedback_parts.append(f"VLM analysis failed: {vlm_response.get('error')}")
    else:
        analysis = vlm_response.get("parsed", {})
        
        if analysis.get("session_active"):
            score += 20
            feedback_parts.append("Session is active (+20)")
        else:
            feedback_parts.append("Session does not appear active")

        if analysis.get("two_band_power_widgets_visible"):
            score += 30
            feedback_parts.append("Two Band Power widgets visible (+30)")
        else:
            feedback_parts.append("Two Band Power widgets NOT found")

        if analysis.get("widget_1_channel_1_isolated"):
            score += 20
            feedback_parts.append("Channel 1 isolated correctly (+20)")
        else:
            feedback_parts.append("Channel 1 not isolated")

        if analysis.get("widget_2_channel_2_isolated"):
            score += 20
            feedback_parts.append("Channel 2 isolated correctly (+20)")
        else:
            feedback_parts.append("Channel 2 not isolated")
            
        feedback_parts.append(f"VLM Note: {analysis.get('explanation', '')}")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }