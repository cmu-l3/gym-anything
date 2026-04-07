#!/usr/bin/env python3
"""
Verifier for configure_alpha_neurofeedback_playback@1

This verification relies primarily on VLM analysis of the agent's trajectory and final screen state.
It checks:
1. Is the OpenBCI GUI running in Playback mode?
2. Is the Focus Widget visible?
3. Is the Focus Widget configured for 'Alpha'?
4. Is the Focus Widget configured for 'Chan 8'?
"""

import json
import os
import sys
import logging
import tempfile
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_configure_alpha_neurofeedback(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the agent configured the Alpha Neurofeedback task correctly.
    """
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: VLM query not available"}

    # 2. Retrieve programmatic results from container
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        # We continue, as visual verification is primary
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Check App State (Anti-gaming)
    if not task_result.get("app_running", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The OpenBCI GUI was not running at the end of the task."
        }

    # 4. VLM Verification
    # We sample frames to see the workflow + the final state
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available for verification."}

    # Construct the VLM prompt
    images = frames + [final_screenshot]
    prompt = """
    You are verifying an OpenBCI GUI task. 
    The goal is to:
    1. Load a playback file.
    2. Display the 'Focus Widget' (a circular widget with a colored ring).
    3. Configure the Focus Widget to monitor 'Alpha' metric.
    4. Configure the Focus Widget to use 'Channel 8' (or 'Chan 8').

    Please analyze the images (especially the last one) and answer:
    
    1. Is the session active (e.g., timeline visible, Start/Stop button shows 'Stop', or data is streaming)?
    2. Is the 'Focus Widget' visible on the dashboard? (Look for a circular gauge widget, often with a face or ring).
    3. Does the Focus Widget explicitly display the text "Alpha"?
    4. Does the Focus Widget explicitly display "Chan 8" or just the number "8" in its channel selector?
    
    Return a JSON object with:
    {
        "session_active": boolean,
        "focus_widget_visible": boolean,
        "metric_alpha_visible": boolean,
        "channel_8_visible": boolean,
        "reasoning": "string explaining what you see"
    }
    """

    try:
        vlm_response = query_vlm(images=images, prompt=prompt)
        # Parse the result (assuming query_vlm returns a dict or the raw string needs parsing)
        # Here we assume the framework handles JSON parsing if we asked for it, 
        # but we handle the case where it returns a raw string or a dict.
        if isinstance(vlm_response, str):
            # Try to extract JSON from string if needed
            # For this template, we assume query_vlm returns a structured dict 'parsed' key or similar
            # If standard gym_anything.vlm returns text, we might need a helper. 
            # We will assume a 'parsed' field exists or the response is the dict.
            pass 
        
        # Safe access to fields (adjust based on actual VLM API response structure)
        # Assuming vlm_response is the dictionary output
        analysis = vlm_response if isinstance(vlm_response, dict) else {}
        
        # If the API returns { "result": "..." }, we might need to parse. 
        # Let's assume the standard interface returns the parsed JSON.
        
    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed due to VLM error: {e}"}

    # Extract criteria
    session_active = analysis.get("session_active", False)
    widget_visible = analysis.get("focus_widget_visible", False)
    metric_alpha = analysis.get("metric_alpha_visible", False)
    chan_8 = analysis.get("channel_8_visible", False)
    reasoning = analysis.get("reasoning", "No reasoning provided.")

    # 5. Scoring
    score = 0
    feedback_lines = [f"VLM Analysis: {reasoning}"]

    if session_active:
        score += 20
        feedback_lines.append("✓ Session is active/playback running.")
    else:
        feedback_lines.append("✗ Session does not appear active.")

    if widget_visible:
        score += 20
        feedback_lines.append("✓ Focus Widget is visible.")
    else:
        feedback_lines.append("✗ Focus Widget not found.")

    if metric_alpha:
        score += 30
        feedback_lines.append("✓ Metric 'Alpha' is selected.")
    else:
        feedback_lines.append("✗ Metric 'Alpha' not visible in widget.")

    if chan_8:
        score += 30
        feedback_lines.append("✓ Channel 8 is selected.")
    else:
        feedback_lines.append("✗ Channel 8 not visible in widget.")

    # Pass threshold
    passed = (score >= 70) and metric_alpha and chan_8

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }