#!/usr/bin/env python3
"""
Verifier for Configure Spectrogram Dual Channels Task.

Verification relies on VLM analysis of the final screenshot because the
internal state of the Spectrogram widget's channel selector is not
exposed via file/API until settings are explicitly saved, and the task
asks to leave the pane open.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spectrogram_config(traj, env_info, task_info):
    """
    Verify the Spectrogram widget configuration using VLM.
    """
    # 1. basic Environment Checks
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    # 2. Retrieve Task Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Check App State
    if not result_data.get("app_was_running", False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was not running at the end of the task."}

    # 4. VLM Verification
    # We use the final screenshot to check the specific settings configuration
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}

    # Construct VLM Prompt
    prompt = """
    You are verifying an OpenBCI GUI configuration task.
    The user was asked to:
    1. Open the "Spectrogram" widget.
    2. Open the "Channels" settings pane inside the Spectrogram widget.
    3. Configure the "Top Plot" (Top Row) to have ONLY Channel 1 and Channel 2 selected.
    4. Configure the "Bottom Plot" (Bottom Row) to have ONLY Channel 7 and Channel 8 selected.
    
    Examine the FINAL screenshot provided (the last image).
    
    Check for the following:
    1. Is the Spectrogram widget visible? (Look for a frequency heatmap or the word "Spectrogram").
    2. Is the Channel Selector settings pane OPEN? (Look for a grid of numbered buttons, usually 8 columns for channels).
    3. In the TOP ROW of the selector: Are buttons 1 and 2 highlighted/colored (active), and buttons 3-8 grey/dark (inactive)?
    4. In the BOTTOM ROW of the selector: Are buttons 7 and 8 highlighted/colored (active), and buttons 1-6 grey/dark (inactive)?
    
    Provide a score breakdown:
    - Widget Visible: 20 pts
    - Settings Pane Open: 20 pts
    - Top Row Correct (1 & 2 only): 30 pts
    - Bottom Row Correct (7 & 8 only): 30 pts
    
    If the pane is not open, you cannot verify the settings, so score 0 for settings.
    
    Return JSON format:
    {
        "widget_visible": boolean,
        "settings_open": boolean,
        "top_row_correct": boolean,
        "bottom_row_correct": boolean,
        "score": integer (0-100),
        "reasoning": "string explanation"
    }
    """

    # Query VLM
    vlm_response = query_vlm(
        prompt=prompt,
        images=trajectory_frames + [final_screenshot]
    )

    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM analysis failed: {vlm_response.get('error')}"}

    parsed = vlm_response.get("parsed", {})
    score = parsed.get("score", 0)
    reasoning = parsed.get("reasoning", "No reasoning provided.")

    # 5. Final Decision
    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Verification Result: {reasoning}"
    }