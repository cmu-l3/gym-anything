#!/usr/bin/env python3
"""
Verifier for configure_emg_channel_selection task.

Task: Configure EMG widget to show ONLY Channels 7 and 8.

Verification Strategy:
1. Primary: VLM analysis of trajectory and final screenshot.
   - Check for EMG widget presence.
   - Count active bars/channels in the widget.
   - Verify specific channels (7 & 8) if labels are legible.
2. Secondary: Application state check (must be running).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_emg_channel_selection(traj, env_info, task_info):
    """
    Verifies that the agent configured the EMG widget correctly.
    """
    # 1. Setup and Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: VLM query function not available"}

    # Read result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Criteria
    app_running = result.get('app_was_running', False)
    screenshot_exists = result.get('screenshot_exists', False)
    
    if not app_running:
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was not running at the end of the task."}

    # 2. VLM Verification
    # We use trajectory frames to confirm the workflow (widget addition, settings interaction)
    # and the final screenshot to verify the final configuration.
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        frames.append(final_img)
    elif not screenshot_exists:
         return {"passed": False, "score": 10, "feedback": "No evidence found (screenshots missing)."}

    prompt = """
    You are verifying an OpenBCI GUI task. 
    The user was asked to:
    1. Start a Synthetic session.
    2. Add the EMG widget.
    3. Configure the EMG widget to show ONLY Channel 7 and Channel 8 (turning off 1-6).

    Examine the provided screenshots, especially the final one.
    
    Answer the following questions in JSON format:
    1. "emg_widget_visible": boolean - Is the EMG widget visible on the dashboard? (Look for a widget labeled 'EMG').
    2. "active_bar_count": integer - How many distinct signal bars or traces are active/moving in the EMG widget? (Default is 8, target is 2).
    3. "channels_7_8_only": boolean - Does it look like only the bottom two channels (7 and 8) are active? 
       (If you see 8 bars but 6 are flat/greyed out and 2 are moving, that counts as success if the goal was to isolate them, but ideally the others should be hidden).
    4. "session_active": boolean - Is data streaming? (Look for 'Stop Data Stream' button or moving graphs).

    Reasoning: Provide a brief explanation of your observations.
    """

    try:
        vlm_response = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_response.get('parsed', {})
        feedback_reason = parsed.get('reasoning', "No reasoning provided.")
        logger.info(f"VLM Analysis: {parsed}")
    except Exception as e:
        logger.error(f"VLM Query failed: {e}")
        return {"passed": False, "score": 20, "feedback": "Verification failed due to VLM error. App was running."}

    # 3. Scoring
    score = 0
    feedback_parts = []

    # App Running (20 pts)
    if app_running:
        score += 20
        feedback_parts.append("Application running.")

    # Session Active (20 pts)
    if parsed.get('session_active', False):
        score += 20
        feedback_parts.append("Session is active.")
    else:
        feedback_parts.append("Session does not appear active.")

    # EMG Widget Visible (20 pts)
    if parsed.get('emg_widget_visible', False):
        score += 20
        feedback_parts.append("EMG widget found.")
    else:
        feedback_parts.append("EMG widget NOT found.")

    # Channel Configuration (40 pts)
    # Strict check: Active bar count should be 2
    # Lenient check: If exactly 2 bars are moving/highlighted
    bar_count = parsed.get('active_bar_count', 8)
    channels_correct = parsed.get('channels_7_8_only', False)

    if channels_correct or bar_count == 2:
        score += 40
        feedback_parts.append("Correctly configured for Channels 7 & 8.")
    elif bar_count < 8 and bar_count != 2:
        score += 10
        feedback_parts.append(f"Partial configuration: {bar_count} channels visible (expected 2).")
    else:
        feedback_parts.append("Channel selection incorrect (default 8 channels likely visible).")

    # Final Pass/Fail
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" [VLM: {feedback_reason}]"
    }