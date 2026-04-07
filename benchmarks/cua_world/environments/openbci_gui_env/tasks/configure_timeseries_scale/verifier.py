#!/usr/bin/env python3
"""
Verifier for configure_timeseries_scale task.

Criteria:
1. OpenBCI GUI must be running (5 pts).
2. Agent must have saved a screenshot as requested (10 pts).
3. VLM Verification of Trajectory/Final State (85 pts):
   - Session must be running (waveforms visible).
   - Vertical Scale set to 200 uV.
   - Time Window set to 10 seconds.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_timeseries_config(traj, env_info, task_info):
    """
    Verifies that the OpenBCI Time Series widget is configured correctly.
    """
    # 1. Setup and read JSON result from container
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. file-based Scoring (15 pts total)
    score = 0
    feedback_log = []
    
    # Check if app is running (5 pts)
    if result.get("app_running", False):
        score += 5
        feedback_log.append("App is running.")
    else:
        feedback_log.append("App was closed (fail).")

    # Check if agent saved the screenshot (10 pts)
    # This proves they followed the specific "save evidence" instruction
    if result.get("agent_screenshot_valid", False):
        score += 10
        feedback_log.append("Agent saved evidence screenshot.")
    elif result.get("agent_screenshot_exists", False):
        score += 5
        feedback_log.append("Agent saved screenshot, but timestamp is suspect.")
    else:
        feedback_log.append("Agent did not save the evidence screenshot to the correct path.")

    # 3. VLM Verification (85 pts total)
    # We check the final state and trajectory to ensure settings were actually applied.
    
    if not query_vlm:
        return {"passed": False, "score": score, "feedback": "VLM not available for visual verification"}

    # Get frames: sample 3 from trajectory + final state
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification"}

    # VLM Prompt
    prompt = """
    Analyze these screenshots of the OpenBCI GUI.
    
    I need to verify three specific things:
    1. Is the data session RUNNING? (Look for streaming waveforms in the main Time Series widget, moving lines, not a flat line or empty grid).
    2. Is the Vertical Scale set to "200 uV"? (Look for a dropdown or label on the left of the Time Series widget saying '200 uV' or '200').
    3. Is the Time Window/Duration set to "10 sec"? (Look for a dropdown or label usually on the right or top of the widget saying '10 sec', '10 s', or just '10').

    Provide your assessment in JSON format:
    {
        "session_running": true/false,
        "vertical_scale_200uv": true/false,
        "time_window_10s": true/false,
        "reasoning": "Explain what values you see for scale and window"
    }
    """
    
    try:
        # We send the last few frames to catch the final state clearly
        vlm_response = query_vlm(images=frames[-2:], prompt=prompt)
        assessment = vlm_response.get('parsed', {})
        
        # Score VLM components
        # Session Running (25 pts)
        if assessment.get('session_running', False):
            score += 25
            feedback_log.append("Session is active.")
        else:
            feedback_log.append("Session does not appear active (no waveforms).")

        # Vertical Scale (30 pts)
        if assessment.get('vertical_scale_200uv', False):
            score += 30
            feedback_log.append("Vertical scale confirmed at 200 uV.")
        else:
            feedback_log.append("Vertical scale incorrect or not found.")

        # Time Window (30 pts)
        if assessment.get('time_window_10s', False):
            score += 30
            feedback_log.append("Time window confirmed at 10s.")
        else:
            feedback_log.append("Time window incorrect or not found.")
            
        feedback_log.append(f"VLM Reasoning: {assessment.get('reasoning', 'None')}")

    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_log.append(f"Visual verification failed due to error: {e}")

    # 4. Final Verdict
    # Pass threshold: 60 points (must have running session and at least one setting correct)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }