#!/usr/bin/env python3
"""
Verifier for navigate_playback_timestamp task.

This task is visual: the agent must load a specific file and pause at a specific time.
Since OpenBCI GUI does not expose playback state via CLI/API, we rely on VLM analysis
of the final screenshot and trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_playback_timestamp(traj, env_info, task_info):
    """
    Verify the agent loaded the Motor Imagery file and paused between 0:08 and 0:12.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was closed or crashed."}

    # 2. VLM Verification
    # We need to verify:
    # A) The correct file is loaded (Look for "MotorImagery" or similar in UI)
    # B) The timestamp is between 0:08 and 0:12
    # C) The playback is paused (implied if they stopped to show the timestamp, but hard to prove statically without video, so we check if the timestamp is specific)
    
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available."}

    prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    1. Read the playback timestamp/timer. It is usually in format MM:SS or MM:SS:MS (e.g., 00:08).
    2. Identify the loaded filename or data source. Look for "MotorImagery", "S001", or "Playback".
    3. Determine if the playback is PAUSED. (Look for a "Play" button icon which implies it's currently paused, or checked if data stream looks frozen/clean).
    
    Return JSON format:
    {
        "timestamp_str": "MM:SS",
        "seconds_value": <float representing total seconds, e.g. 10.5>,
        "filename_visible": <bool>,
        "is_motor_imagery": <bool>,
        "is_paused": <bool or "uncertain">
    }
    """

    vlm_response = query_vlm(
        prompt=prompt,
        image=final_screenshot,
        model="gpt-4o" # or equivalent high-capability model
    )

    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed."}

    data = vlm_response.get("parsed", {})
    
    # Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Correct File Loaded (30 pts)
    if data.get("is_motor_imagery") or data.get("filename_visible"):
        score += 30
        feedback.append("Correct file loaded.")
    else:
        feedback.append("Could not confirm 'Motor Imagery' file loaded.")

    # Criterion 2: Timestamp Accuracy (50 pts)
    # Target: 00:08 to 00:12
    try:
        timestamp_sec = float(data.get("seconds_value", -1))
        if 8.0 <= timestamp_sec <= 12.0:
            score += 50
            feedback.append(f"Timestamp {timestamp_sec}s is within target range (8-12s).")
        elif timestamp_sec > 0:
            feedback.append(f"Timestamp {timestamp_sec}s is outside target range (8-12s).")
        else:
            feedback.append("Could not read valid timestamp.")
    except (ValueError, TypeError):
        feedback.append("Could not parse timestamp value.")

    # Criterion 3: Paused State (20 pts)
    # If the agent nailed the timestamp, they likely paused it. 
    # If VLM explicitly says paused, grant points. If uncertain but timestamp is perfect, grant points.
    if data.get("is_paused") is True or (data.get("is_paused") == "uncertain" and 8.0 <= timestamp_sec <= 12.0):
        score += 20
        feedback.append("Playback appears paused.")
    else:
        feedback.append("Could not confirm playback is paused.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }