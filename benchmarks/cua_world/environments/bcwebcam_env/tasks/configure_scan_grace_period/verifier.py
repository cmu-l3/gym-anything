#!/usr/bin/env python3
"""
Verifier for configure_scan_grace_period task.

Verification Strategy:
1. File Content: The bcWebCam.ini file must contain `BcGracePeriod=1500` under `[General]`.
2. Anti-gaming Timestamp: The file must have been modified after the task started.
3. Process Lifecycle: The application must be running, AND its start time must be 
   AFTER the file was modified. This ensures the app was properly restarted to load the new config.
4. VLM Verification: Agent trajectory shows evidence of file editing and software restarting.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from a Windows desktop agent performing an IT configuration task.
The agent was asked to edit the 'bcWebCam.ini' file to set 'BcGracePeriod=1500' and then restart the bcWebCam application.

Look at the frames chronologically and determine:
1. Is there any visual evidence of the agent editing a configuration file? (e.g., Notepad open showing the INI file, or using PowerShell/cmd).
2. Is the bcWebCam application visible in the final frame (indicating it was successfully reopened)?

Respond in JSON format:
{
    "file_editing_visible": true/false,
    "app_visible_at_end": true/false,
    "observations": "brief explanation"
}
"""

def verify_configure_scan_grace_period(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use Windows path to where the export script saved the result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    file_exists = result.get('file_exists', False)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    app_running = result.get('app_running', False)
    proc_start_time = result.get('proc_start_time', 0)
    ini_content = result.get('ini_content', "")

    # 1. File Modification (10 points)
    if file_exists and file_mtime >= task_start:
        score += 10
        feedback_parts.append("INI file modified during task.")
    elif file_exists:
        feedback_parts.append("INI file exists but was not modified.")
    else:
        feedback_parts.append("bcWebCam.ini not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Parse INI content manually to ensure structural correctness (no configparser exceptions)
    lines = ini_content.splitlines()
    in_general = False
    found_key = False
    correct_value = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith(';') or line.startswith('#'):
            continue
        
        # Track active section
        if line.startswith('[') and line.endswith(']'):
            if line.lower() == '[general]':
                in_general = True
            else:
                in_general = False
            continue

        # Check for key under [General]
        if in_general and '=' in line:
            key, val = line.split('=', 1)
            if key.strip().lower() == 'bcgraceperiod':
                found_key = True
                if val.strip() == '1500':
                    correct_value = True

    # 2. Content Correctness (30 points)
    if found_key and correct_value:
        score += 30
        feedback_parts.append("BcGracePeriod=1500 correctly set under [General].")
    elif found_key:
        feedback_parts.append(f"BcGracePeriod found, but value is incorrect.")
    else:
        feedback_parts.append("BcGracePeriod setting not found under [General] section.")

    # 3. Process Lifecycle / App Restart (40 points)
    # The agent must restart the application AFTER saving the file.
    if app_running:
        # Give a 2-second buffer for file save / process launch race conditions
        if proc_start_time >= (file_mtime - 2):
            score += 40
            feedback_parts.append("App was successfully restarted to load the new config.")
        else:
            feedback_parts.append("App is running but was NOT restarted after file modification (old config still in memory).")
    else:
        feedback_parts.append("App is not currently running.")

    # 4. VLM Trajectory Verification (20 points)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("file_editing_visible"):
                score += 10
                feedback_parts.append("VLM: File editing trajectory confirmed.")
            if parsed.get("app_visible_at_end"):
                score += 10
                feedback_parts.append("VLM: App visibility confirmed.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Pass Requirements: File must have correct content AND the app must be running with the new config.
    key_criteria_met = correct_value and app_running and (proc_start_time >= (file_mtime - 2))
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }