#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_terminate_runaway_process(traj, env_info, task_info):
    """
    Verify that the runaway process was terminated and the safe process was preserved.
    Also checks if the Webmin UI was used via VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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

    score = 0
    feedback_parts = []

    # 2. Check Process States
    target_running = result.get("target_running", True)
    safe_running = result.get("safe_running", False)

    # Criterion 1: Target terminated (50 pts)
    if not target_running:
        score += 50
        feedback_parts.append("Target process terminated successfully")
    else:
        feedback_parts.append("Target process is still running")

    # Criterion 2: Safe process preserved (40 pts)
    if safe_running:
        score += 40
        feedback_parts.append("Safe process preserved")
    else:
        feedback_parts.append("Safe process was incorrectly terminated")

    # 3. VLM Verification for UI Usage (10 pts)
    # We want to ensure they used the "Running Processes" module in Webmin
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Review these screenshots of a user interacting with Virtualmin/Webmin.
    Did the user navigate to the 'Running Processes' or 'Process Manager' module?
    Look for a table listing PIDs, CPU usage, and command names.
    Look for action buttons like 'Kill', 'Terminate', or 'Signal'.
    
    Return JSON: {"ui_used": true/false, "reason": "..."}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    ui_used = False
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        ui_used = parsed.get("ui_used", False)
        if ui_used:
            score += 10
            feedback_parts.append("Webmin process manager interface used")
        else:
            feedback_parts.append("Webmin process manager interface usage not detected")
    else:
        feedback_parts.append("VLM verification failed")

    # Final Pass Check
    # Must have killed target AND saved safe process (90 pts minimum from logic)
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }