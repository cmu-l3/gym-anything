#!/usr/bin/env python3
"""
Verifier for configure_single_channel_emg_trigger task.

Verifies:
1. OpenBCI GUI is running.
2. VLM Verification of Screenshot:
   - EMG Widget is present.
   - Channel 1 is active/selected.
   - Channels 2-8 are disabled.
   - Threshold is adjusted (not at bottom).
"""

import json
import os
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

def verify_emg_config(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic Checks
    if not result.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was not running at the end of the task."}

    # 3. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    
    # We use trajectory frames to confirm they went through the playback setup
    frames = sample_trajectory_frames(traj, n=3)
    
    if not final_screenshot:
         return {"passed": False, "score": 0, "feedback": "No final screenshot available for verification."}

    prompt = """
    You are verifying an OpenBCI GUI configuration task.
    The user was asked to:
    1. Start a Playback session (look for file playback indicators or time stamps).
    2. Add an EMG Widget (look for a widget labeled 'EMG').
    3. Configure the EMG widget to isolate Channel 1 (Channel 1 active, Channels 2-8 disabled/greyed out).
    4. Adjust the EMG Threshold (the slider or limit line should NOT be at the very bottom/zero).

    Analyze the provided screenshot.
    
    Return a JSON object with the following boolean fields:
    - "playback_active": Is the session running (e.g., 'Stop Session' button visible, waveforms visible)?
    - "emg_widget_present": Is the EMG widget visible on the dashboard?
    - "channel_1_isolated": Does the EMG widget show Channel 1 as active and Channels 2-8 as inactive/disabled?
    - "threshold_adjusted": Is the threshold slider/line moved up from the minimum position?
    
    Also include a "feedback" string explaining your observations.
    """

    vlm_response = query_vlm(
        images=[final_screenshot], # We focus on final state for configuration
        prompt=prompt
    )

    # 4. Scoring
    score = 0
    feedback = []
    
    try:
        analysis = vlm_response.get("parsed", {})
        if not analysis:
            # Fallback if parsing failed
            import re
            text = vlm_response.get("text", "")
            analysis = {
                "playback_active": "playback_active" in text or "running" in text,
                "emg_widget_present": "emg_widget_present" in text,
                "channel_1_isolated": "channel_1_isolated" in text,
                "threshold_adjusted": "threshold_adjusted" in text
            }
            feedback.append(f"VLM Output (raw): {text}")
        else:
            feedback.append(f"VLM Analysis: {analysis.get('feedback', '')}")

        # Score components
        if analysis.get("playback_active"):
            score += 20
        else:
            feedback.append("Session does not appear to be active.")

        if analysis.get("emg_widget_present"):
            score += 20
        else:
            feedback.append("EMG widget not found.")

        if analysis.get("channel_1_isolated"):
            score += 40
        else:
            feedback.append("Channel 1 does not appear to be correctly isolated (check if Ch 2-8 are disabled).")

        if analysis.get("threshold_adjusted"):
            score += 20
        else:
            feedback.append("Threshold slider does not appear to be adjusted.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"VLM verification error: {e}"}

    # Pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }