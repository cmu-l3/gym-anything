#!/usr/bin/env python3
"""
Verifier for configure_system_health_alerts task.

Verification Strategy:
1. VLM Trajectory Analysis: Verify the agent navigated to "Alert Me" / "System Health".
2. VLM Final Check: specific settings (Disk Space 2GB, Data Collection checked, Email set).
3. Programmatic: Ensure result file exists and app was running.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_health_alerts(traj, env_info, task_info):
    """
    Verify the 'Alert Me' settings configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_disk = metadata.get('expected_disk_threshold', '2048')
    expected_email = metadata.get('expected_email', 'soc-alerts@bank.local')

    score = 0
    feedback_parts = []
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Basic Sanity Checks
    if result_data.get('app_running', False):
        score += 10
        feedback_parts.append("ADAudit Plus is running.")
    else:
        feedback_parts.append("ADAudit Plus is NOT running.")

    # 3. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No final screenshot available."}
    
    # Prepare Prompt
    prompt = f"""
    You are verifying if a user correctly configured 'Alert Me' settings in ManageEngine ADAudit Plus.
    
    Task Requirements:
    1. Navigate to 'Alert Me' or 'System Health' settings in Admin.
    2. Enable 'Disk Space Alert' and set threshold to approx 2 GB (or 2048 MB).
    3. Enable 'Data Collection Alert'.
    4. Set email to '{expected_email}'.
    
    Examine the images (trajectory and final state).
    
    Return JSON with:
    - "page_accessed": boolean (did they reach the settings page?)
    - "disk_alert_enabled": boolean
    - "disk_threshold_correct": boolean (is 2 or 2048 visible?)
    - "data_collection_alert_enabled": boolean
    - "email_correct": boolean (is {expected_email} visible?)
    - "settings_saved": boolean (any visual confirmation of save, or form filled correctly in final state)
    """
    
    # Query VLM
    vlm_images = frames + [final_screenshot]
    vlm_result = query_vlm(images=vlm_images, prompt=prompt)
    
    if not vlm_result.get("success"):
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
    else:
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("page_accessed"):
            score += 20
            feedback_parts.append("Navigated to Alert settings.")
            
        if parsed.get("disk_alert_enabled"):
            score += 15
            feedback_parts.append("Disk alert enabled.")
            
        if parsed.get("disk_threshold_correct"):
            score += 15
            feedback_parts.append(f"Disk threshold set to {expected_disk}.")
        else:
            feedback_parts.append("Disk threshold incorrect or not visible.")
            
        if parsed.get("data_collection_alert_enabled"):
            score += 15
            feedback_parts.append("Data collection alert enabled.")
            
        if parsed.get("email_correct"):
            score += 15
            feedback_parts.append(f"Email set to {expected_email}.")
            
        if parsed.get("settings_saved") or (parsed.get("email_correct") and parsed.get("disk_threshold_correct")):
            score += 10
            feedback_parts.append("Settings appear saved/filled.")

    # Final Score Calculation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }