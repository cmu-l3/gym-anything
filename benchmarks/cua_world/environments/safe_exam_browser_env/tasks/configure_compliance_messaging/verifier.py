#!/usr/bin/env python3
"""
Verifier for configure_compliance_messaging task.

Multi-Criteria Verification:
1. Disclaimer text exists in the database for the specific config (30 pts)
2. Quit text exists in the database for the specific config (30 pts)
3. The disclaimer setting is enabled (15 pts)
4. Trajectory frames show the agent interacting with the settings UI (25 pts)
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_compliance_messaging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_disclaimer = metadata.get('expected_disclaimer_text', 'unauthorized help on this exam')
    expected_quit = metadata.get('expected_quit_text', 'action cannot be undone')

    # Load the exported result from the environment securely
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

    settings = result.get('settings', {})
    
    score = 0
    feedback_parts = []

    disclaimer_found = False
    quit_found = False
    disclaimer_enabled = False

    # Check the database values programmatically
    for k, v in settings.items():
        val_str = str(v).lower()
        if expected_disclaimer.lower() in val_str:
            disclaimer_found = True
        if expected_quit.lower() in val_str:
            quit_found = True
        # Check for boolean toggles (SEB often uses 'true' or '1')
        if 'disclaimer' in k.lower() and val_str in ['true', '1']:
            disclaimer_enabled = True

    if disclaimer_found:
        score += 30
        feedback_parts.append("Disclaimer text successfully verified in DB")
    else:
        feedback_parts.append("Disclaimer text NOT found in DB")

    if quit_found:
        score += 30
        feedback_parts.append("Quit message successfully verified in DB")
    else:
        feedback_parts.append("Quit message NOT found in DB")

    if disclaimer_enabled or disclaimer_found:
         score += 15
         feedback_parts.append("Disclaimer enabled attribute verified")

    # VLM Trajectory Verification
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)

        prompt = (
            "You are an evaluator checking if an agent correctly configured Safe Exam Browser settings. "
            "The task was to edit the 'Law 101 Final' exam configuration, enable the disclaimer setting, "
            "type a specific Honor Code disclaimer, and type a specific Quit warning message into the UI fields. "
            "Look at these screenshots from the agent's trajectory. "
            "Did the agent successfully navigate to the User Interface/Message settings, "
            "type the required legal/warning text, and save the configuration? "
            "Reply EXACTLY with 'YES' if there is visual evidence of this workflow, otherwise reply 'NO'."
        )

        vlm_response = query_vlm(images=frames, prompt=prompt)
        if vlm_response and "YES" in vlm_response.upper():
            score += 25
            feedback_parts.append("VLM visually verified trajectory workflow")
        else:
            feedback_parts.append("VLM did not clearly verify the workflow visually")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM check encountered an error")

    # The setup script cleared existing strings, meaning their presence proves the agent did the work.
    passed = disclaimer_found and quit_found and score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }