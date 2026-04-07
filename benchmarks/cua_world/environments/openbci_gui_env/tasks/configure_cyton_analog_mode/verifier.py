#!/usr/bin/env python3
"""
Verifier for configure_cyton_analog_mode task.

Criteria:
1. Evidence: Agent saved a screenshot to the correct path (20 pts)
2. VLM: Hardware Settings panel was opened (20 pts)
3. VLM: 'Analog' mode was selected in the dropdown (40 pts)
4. VLM: 'Send' button was clicked (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_cyton_analog_mode(traj, env_info, task_info):
    """
    Verify the agent configured the Cyton board to Analog mode.
    """
    # 1. Setup - Get programmatic results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Programmatic Evidence (20 pts)
    score = 0
    feedback_log = []
    
    evidence_exists = result_data.get("evidence_screenshot_exists", False)
    evidence_fresh = result_data.get("evidence_screenshot_created_during_task", False)
    
    if evidence_exists and evidence_fresh:
        score += 20
        feedback_log.append("Evidence screenshot saved correctly (+20)")
    elif evidence_exists:
        score += 10
        feedback_log.append("Evidence screenshot exists but timestamp is old (+10)")
    else:
        feedback_log.append("No evidence screenshot found at expected path (0/20)")

    # 3. Score VLM Analysis (80 pts)
    # We need to check the trajectory for the settings panel interaction
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": score, "feedback": "VLM missing, cannot verify UI actions"}

    # Sample frames to catch the interaction
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    prompt = """
    You are verifying an OpenBCI GUI task. The user must:
    1. Open the 'Hardware Settings' panel.
    2. Change 'Board Mode' to 'Analog'.
    3. Click 'Send'.

    Analyze the provided screenshots of the session.
    
    Q1: Is the 'Hardware Settings' panel visible in any frame? (It is a popup or overlay menu with dropdowns for Channel Count, Board Mode, etc.)
    Q2: Is the 'Board Mode' dropdown set to 'Analog' (or 'Analog Mode') in any frame?
    Q3: Did the user click the 'Send' button inside the Hardware Settings panel? (Look for mouse cursor over 'Send' or the panel closing after a setting change).

    Output JSON:
    {
        "settings_panel_opened": boolean,
        "analog_mode_selected": boolean,
        "send_clicked": boolean,
        "reasoning": "string"
    }
    """

    try:
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        analysis = vlm_resp.get('parsed', {})
        
        # Check Q1: Panel Opened (20 pts)
        if analysis.get("settings_panel_opened", False):
            score += 20
            feedback_log.append("Hardware Settings panel opened (+20)")
        else:
            feedback_log.append("Hardware Settings panel not detected")

        # Check Q2: Analog Selected (40 pts)
        if analysis.get("analog_mode_selected", False):
            score += 40
            feedback_log.append("Analog mode selection confirmed (+40)")
        else:
            feedback_log.append("Analog mode not seen selected")

        # Check Q3: Send Clicked (20 pts)
        if analysis.get("send_clicked", False):
            score += 20
            feedback_log.append("Send button click confirmed (+20)")
        else:
            feedback_log.append("Send button click not detected")
            
        feedback_log.append(f"VLM Reasoning: {analysis.get('reasoning', 'None')}")

    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_log.append(f"VLM verification error: {str(e)}")

    # 4. Final Verdict
    # Threshold: Need at least 80 points (Must have selected Analog and either Saved Evidence or Clicked Send)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_log)
    }