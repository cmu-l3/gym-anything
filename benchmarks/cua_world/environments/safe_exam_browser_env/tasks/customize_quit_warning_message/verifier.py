#!/usr/bin/env python3
"""
Verifier for customize_quit_warning_message task.

Verification Strategy:
1. Primary DB Check: Verifies the precise target string exists inside SEB Server's MariaDB.
2. VLM Trajectory: Verifies the agent actually navigated the User Interface dialog settings to prevent 'typing the string in the description box' gaming.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are evaluating an agent that is configuring the Safe Exam Browser Server.
The agent was asked to set a custom "Quit Confirmation Message" to "WARNING: Quitting will SUBMIT your exam permanently."

Analyze these trajectory frames and determine:
1. Did the agent navigate to the "User Interface" (or Browser/Dialogs) settings tab?
2. Did the agent enter the exact warning text into a Quit Message or Quit Confirmation field? (Not just into a generic description box).

Respond ONLY in valid JSON format:
{
    "navigated_to_ui_settings": true/false,
    "entered_text_in_correct_field": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_customize_quit_warning_message(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution error: copy_from_env not available"}

    # Extract JSON results from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    config_exists = int(result.get('config_exists', 0))
    text_in_config = result.get('text_in_config', False)
    text_in_db = result.get('text_in_db', False)

    # Criterion 1: Target Exam Configuration exists (20 points)
    if config_exists > 0:
        score += 20
        feedback_parts.append("Exam configuration found")
    else:
        feedback_parts.append("Target exam configuration missing")

    # Criterion 2: Target text correctly committed to database (40 points)
    if text_in_config:
        score += 40
        feedback_parts.append("Target text found specifically in configuration data")
    elif text_in_db:
        score += 30
        feedback_parts.append("Target text found in database fallback check")
    else:
        feedback_parts.append("Target text NOT found in database")

    # Criterion 3: VLM Verification of workflow (40 points)
    # We take 4 samples throughout the trajectory plus the final screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames

    if images:
        try:
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            parsed_res = vlm_response.get('parsed', {})
            
            nav_ui = parsed_res.get('navigated_to_ui_settings', False)
            correct_field = parsed_res.get('entered_text_in_correct_field', False)
            
            if nav_ui and correct_field:
                score += 40
                feedback_parts.append("VLM verified correct UI configuration workflow")
            elif nav_ui:
                score += 15
                feedback_parts.append("VLM noted UI navigation but not correct text entry")
            else:
                feedback_parts.append("VLM did not verify proper UI dialog workflow")
                
            logger.info(f"VLM reasoning: {parsed_res.get('reasoning', 'none')}")
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            feedback_parts.append("VLM evaluation skipped/failed")

    # Ensure "do nothing" fails
    key_criteria_met = (text_in_config or text_in_db) and (config_exists > 0)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }