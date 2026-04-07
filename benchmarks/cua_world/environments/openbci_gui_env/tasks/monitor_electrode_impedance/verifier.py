#!/usr/bin/env python3
"""
Verifier for Monitor Electrode Impedance task.
Uses VLM to verify that the Impedance Widget is visible and channels 1 & 2 are active.
"""

import json
import os
import tempfile
import logging

# Import framework VLM utilities
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_monitor_electrode_impedance(traj, env_info, task_info):
    """
    Verify the impedance monitoring task.
    
    Criteria:
    1. OpenBCI GUI is running.
    2. Impedance Widget is visible on the dashboard.
    3. Channel 1 is active (checking impedance).
    4. Channel 2 is active (checking impedance).
    5. Channels 3-8 are inactive.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic file-based results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Check if app was running (10 pts)
    if result.get("app_was_running", False):
        score += 10
    else:
        feedback_parts.append("OpenBCI GUI was not running at the end.")

    # Check if agent saved the screenshot (10 pts)
    if result.get("agent_screenshot_exists", False) and result.get("agent_screenshot_created_during_task", False):
        score += 10
        feedback_parts.append("Agent saved evidence screenshot.")
        # Try to use agent's screenshot for VLM if available, otherwise use system final
        # Note: In this framework, we usually rely on trajectory/final system screenshot 
        # for trust, but we can verify the agent's specific crop if desired. 
        # We will prioritize the system final screenshot for state verification.
    else:
        feedback_parts.append("Agent did not save the requested screenshot.")

    # 2. VLM Verification (80 pts)
    # We check the final state of the GUI
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for VLM verification."}

    # Construct VLM prompt
    prompt = """
    You are verifying an OpenBCI GUI task. 
    The goal is to display the 'Impedance Widget' and activate channels 1 and 2 ONLY.
    
    Analyze the screenshot and answer in JSON:
    1. "impedance_widget_visible": boolean - Is the 'Impedance' widget visible? (Look for text 'Impedance' or 'Ohm' or 'kOhm' or buttons labeled 1-8 in a grid/circle).
    2. "channel_1_active": boolean - Is Channel 1 active/checking? (The button for '1' should look pressed/colored/highlighted compared to inactive ones).
    3. "channel_2_active": boolean - Is Channel 2 active/checking?
    4. "others_inactive": boolean - Are channels 3, 4, 5, 6, 7, 8 inactive/greyed out?
    5. "values_visible": boolean - Do you see impedance values (numbers ending in kOhm or similar) for the active channels?
    """

    vlm_response = query_vlm(
        prompt=prompt,
        image=final_screenshot
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM analysis failed: {vlm_response.get('error')}"}

    parsed = vlm_response.get("parsed", {})
    
    # Scoring VLM results
    if parsed.get("impedance_widget_visible", False):
        score += 30
        feedback_parts.append("Impedance widget is visible.")
    else:
        feedback_parts.append("Impedance widget NOT found.")

    if parsed.get("channel_1_active", False):
        score += 15
        feedback_parts.append("Channel 1 is active.")
    else:
        feedback_parts.append("Channel 1 is NOT active.")

    if parsed.get("channel_2_active", False):
        score += 15
        feedback_parts.append("Channel 2 is active.")
    else:
        feedback_parts.append("Channel 2 is NOT active.")

    if parsed.get("others_inactive", False):
        score += 10
        feedback_parts.append("Other channels correctly inactive.")
    else:
        feedback_parts.append("Some other channels are incorrectly active.")

    if parsed.get("values_visible", False):
        score += 10
        feedback_parts.append("Impedance values are visible (stream running).")

    # Final Pass/Fail determination
    # Need at least Widget + Ch1 + Ch2 (approx 10+10+30+15+15 = 80)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }