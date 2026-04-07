#!/usr/bin/env python3
"""
Verifier for configure_duplicate_filter task in bcWebCam.

Uses robust multi-signal verification:
1. Programmatic: Extracts Windows INI config file from container to verify presence of the target value
2. Programmatic: Checks file modification timestamps to prevent 'do nothing' gaming
3. VLM Trajectory: Uses multiple frames to verify the agent actually navigated the UI
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a task to configure the bcWebCam application.
Task: Enable duplicate barcode filtering (often called "Same barcode delay" or "Ignore duplicate") and set the delay to 5000 milliseconds (5 seconds).

Review the sequence of screenshots from the agent's screen. Answer the following questions:
1. opened_settings: Did the agent open the Options/Settings dialog in bcWebCam?
2. found_setting: Did the agent locate the setting for duplicate barcode delay / same barcode delay?
3. entered_value: Did the agent enter the value '5000' (or '5') for this setting?
4. clicked_ok: Did the agent click 'OK' or 'Apply' to save the settings?

Respond strictly in JSON format:
{
    "opened_settings": true/false,
    "found_setting": true/false,
    "entered_value": true/false,
    "clicked_ok": true/false
}
"""

def verify_configure_duplicate_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Evaluate exported programmatic data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load task_result.json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    ini_modified = result.get('ini_modified_during_task', False)
    ini_content = result.get('ini_content', '')

    if ini_modified:
        feedback_parts.append("Programmatic: Settings INI file was modified during task.")
        score += 15
    else:
        feedback_parts.append("Programmatic: INI not modified (App may not write until closed).")
    
    # Check for 5000 or 5 in INI content
    # Look for value presence near typical bcWebCam configuration keys
    stripped_ini = ini_content.replace(" ", "").replace('"', '')
    if "5000" in stripped_ini or "Delay=5" in stripped_ini or "Timeout=5" in stripped_ini:
        feedback_parts.append("Programmatic: Value '5000' or '5' found in configuration.")
        score += 25
    
    # 2. Evaluate Trajectory using VLM
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("opened_settings", False):
                    score += 15
                    feedback_parts.append("VLM: Opened settings dialog.")
                if parsed.get("found_setting", False):
                    score += 15
                    feedback_parts.append("VLM: Found duplicate filter setting.")
                if parsed.get("entered_value", False):
                    score += 20
                    feedback_parts.append("VLM: Entered value 5000.")
                if parsed.get("clicked_ok", False):
                    score += 10
                    feedback_parts.append("VLM: Clicked OK to save.")
            else:
                feedback_parts.append("VLM query failed or returned invalid format.")
    except ImportError:
        feedback_parts.append("VLM libraries unavailable. Skipping trajectory evaluation.")
        # Scale score up if we only have programmatic evaluation available
        if score > 0:
            score = int((score / 40.0) * 100)

    # Calculate final grade
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }