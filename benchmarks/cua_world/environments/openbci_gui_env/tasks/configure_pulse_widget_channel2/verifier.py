#!/usr/bin/env python3
"""
Verifier for configure_pulse_widget_channel2 task.

Verifies:
1. OpenBCI GUI is running.
2. Pulse widget is visible on the dashboard.
3. Pulse widget is configured to Channel 2.
4. User saved a screenshot as requested.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pulse_widget_channel2(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Parse JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Basic Requirements (File & App State)
    app_running = result.get("app_was_running", False)
    screenshot_exists = result.get("screenshot_exists", False)
    screenshot_fresh = result.get("screenshot_created_during_task", False)

    if app_running:
        score += 10
        feedback_parts.append("App is running (+10)")
    else:
        feedback_parts.append("App is NOT running")

    if screenshot_exists and screenshot_fresh:
        score += 10
        feedback_parts.append("Screenshot saved correctly (+10)")
    elif screenshot_exists:
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is old (+5)")
    else:
        feedback_parts.append("Screenshot file missing")

    # 3. VLM Verification of Trajectory & Final State
    # We combine trajectory frames (to see action) and the final screenshot (to see result)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        return {"passed": False, "score": score, "feedback": "No visual evidence available for verification."}

    vlm_prompt = """
    You are verifying an OpenBCI GUI task.
    
    Goal: Add the 'Pulse' widget and configure it to 'Channel 2'.
    
    Examine the screenshots (chronological order) and the final screen.
    Answer the following questions in JSON format:
    
    1. "session_started": Is the OpenBCI GUI showing active data streaming (wavy lines in Time Series, or 'Stop Data Stream' button visible)?
    2. "pulse_widget_visible": Is the Pulse widget visible on the dashboard? (Look for a widget labeled 'Pulse' or with a heart/BPM display).
    3. "channel_2_selected": Does the Pulse widget explicitly show "Channel 2", "Ch 2", or "2" as its source? 
       (Note: Default is often Channel 1. Look closely at the widget's settings text or dropdown).
    
    JSON Output Format:
    {
      "session_started": true/false,
      "pulse_widget_visible": true/false,
      "channel_2_selected": true/false,
      "reasoning": "Explain what you see regarding the Pulse widget and its channel setting."
    }
    """

    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        analysis = vlm_response.get("parsed", {})
        
        # Scoring VLM Results
        if analysis.get("session_started", False):
            score += 20
            feedback_parts.append("Session started (+20)")
        else:
            feedback_parts.append("Session not active")

        if analysis.get("pulse_widget_visible", False):
            score += 30
            feedback_parts.append("Pulse widget added (+30)")
        else:
            feedback_parts.append("Pulse widget not found")

        if analysis.get("channel_2_selected", False):
            score += 30
            feedback_parts.append("Channel 2 configured (+30)")
        else:
            feedback_parts.append("Channel 2 NOT detected in Pulse widget settings")

        feedback_parts.append(f"VLM reasoning: {analysis.get('reasoning', 'None')}")

    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("VLM verification failed")

    # Pass Threshold
    # Must have app running + session started + widget visible + channel 2 selected
    # Total possible: 10 + 10 + 20 + 30 + 30 = 100
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }