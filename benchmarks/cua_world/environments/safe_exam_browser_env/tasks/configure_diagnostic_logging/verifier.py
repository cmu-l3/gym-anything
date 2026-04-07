#!/usr/bin/env python3
"""
Verifier for configure_diagnostic_logging task.

Uses a combination of programmatic Database verification (exported via JSON) 
and VLM-based trajectory analysis to reliably grade the task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on the Safe Exam Browser Server UI.
The agent was tasked to create a new Exam Configuration named 'Engineering Basics - DEBUG'.
Specifically, it needed to:
1. Set 'Quit Password' to 'logcheck!23' (General Tab)
2. Enable 'Show Quit Button' (User Interface Tab)
3. Set 'Log Level' to 'Debug' (Security Tab)

Look closely at the trajectory screenshots.
Provide a JSON response containing:
{
    "interacted_with_general_tab": true/false,
    "interacted_with_ui_tab": true/false,
    "interacted_with_security_tab": true/false,
    "saw_logcheck_password_entered": true/false,
    "saw_debug_log_level_selected": true/false,
    "saw_quit_button_enabled": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly explain what you see in the screenshots indicating success or failure"
}
"""

def verify_configure_diagnostic_logging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Read exported programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_diagnostic_logging_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    config_exists = result.get('config_exists', False)
    attributes = result.get('attributes', {})
    
    # DB Checks
    db_quit_password = attributes.get('quitPassword', attributes.get('hashedQuitPassword', ''))
    db_show_quit = attributes.get('showQuitButton', '')
    db_log_level = attributes.get('logLevel', '')

    # 2. Query VLM as secondary/fallback verification
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_result = {"parsed": {}}
    if frames:
        try:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            logger.info(f"VLM verification result: {vlm_result}")
        except Exception as e:
            logger.error(f"VLM query failed: {e}")

    vlm_parsed = vlm_result.get("parsed", {})

    # Evaluate Criterion 1: Configuration Created (30 pts)
    if config_exists:
        score += 30
        feedback_parts.append("Exam Configuration 'Engineering Basics - DEBUG' created")
    else:
        feedback_parts.append("Failed to create Exam Configuration")

    # Evaluate Criterion 2: Log Level (25 pts)
    # 3 in SEB usually represents Debug, 4 represents Verbose. Accept either text or enum values.
    if db_log_level in ['3', '4', 'Debug'] or vlm_parsed.get("saw_debug_log_level_selected"):
        score += 25
        feedback_parts.append("Log Level set to Debug")
    else:
        feedback_parts.append("Log Level not configured correctly")

    # Evaluate Criterion 3: Quit Password (25 pts)
    if db_quit_password or vlm_parsed.get("saw_logcheck_password_entered"):
        score += 25
        feedback_parts.append("Quit Password configured")
    else:
        feedback_parts.append("Quit Password not set")

    # Evaluate Criterion 4: Show Quit Button (20 pts)
    if db_show_quit in ['1', 'true', 'True'] or vlm_parsed.get("saw_quit_button_enabled"):
        score += 20
        feedback_parts.append("Show Quit Button enabled")
    else:
        feedback_parts.append("Show Quit Button not enabled")

    # Final logic
    passed = score >= 80 and config_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "db_attributes": attributes,
            "vlm_reasoning": vlm_parsed.get("reasoning", "No VLM reasoning available")
        }
    }