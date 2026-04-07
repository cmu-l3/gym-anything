#!/usr/bin/env python3
"""
Verifier for configure_silent_log_source_alert task.
Verifies that the agent created a specific 'Device Down' alert profile.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_silent_log_source_alert(traj, env_info, task_info):
    """
    Verify the alert configuration using DB evidence and VLM trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_profile_name', 'Critical_Log_Gap_Alert')
    expected_email = metadata.get('expected_email', 'soc_team@example.com')
    expected_interval = metadata.get('expected_interval_minutes', 15)

    # 1. Load DB Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic Verification (DB)
    # ---------------------------------------------------------
    profile_found = result.get('profile_found', False)
    profile_name = result.get('profile_name', '')
    time_interval = result.get('time_interval', '')
    email_configured = result.get('email_configured', False)

    # Criterion 1: Profile Created (30 pts)
    if profile_found and profile_name == expected_name:
        score += 30
        feedback_parts.append(f"Alert profile '{profile_name}' created.")
    else:
        feedback_parts.append(f"Alert profile '{expected_name}' NOT found in database.")

    # Criterion 2: Correct Interval (20 pts)
    # DB might store as minutes (15) or seconds (900). Check both.
    interval_match = False
    try:
        val = int(time_interval)
        if val == expected_interval or val == (expected_interval * 60):
            interval_match = True
    except:
        pass

    if profile_found and interval_match:
        score += 20
        feedback_parts.append(f"Time interval set correctly to {time_interval}.")
    elif profile_found:
        feedback_parts.append(f"Time interval incorrect (found: {time_interval}, expected: {expected_interval}m).")

    # Criterion 3: Email Configured (15 pts)
    if email_configured:
        score += 15
        feedback_parts.append(f"Email notification configured for {expected_email}.")
    else:
        # Don't penalize too heavily if DB query missed the complex join, VLM can rescue
        feedback_parts.append("Email configuration not confirmed via DB.")

    # ---------------------------------------------------------
    # VLM Verification (Trajectory) (35 pts)
    # ---------------------------------------------------------
    # We use VLM to verify the "silent/no-logs" logic and confirm email if DB missed it.
    
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)

    vlm_prompt = f"""
    You are verifying if an agent configured a specific SIEM alert.
    
    Target Configuration:
    1. Profile Name: '{expected_name}'
    2. Condition: "No logs received" or "Device Down" for 15 minutes.
    3. Notification: Email to '{expected_email}'.
    
    Look at the screenshots. 
    - Do you see the alert profile list with '{expected_name}'?
    - Do you see settings showing '15 minutes' and 'No data'/'No logs'?
    - Do you see an email action configured?
    
    Return JSON:
    {{
        "profile_visible": true/false,
        "condition_correct": true/false,
        "email_visible": true/false,
        "confidence": "high/medium/low"
    }}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result else {}
    
    vlm_score = 0
    if vlm_data.get('profile_visible'):
        vlm_score += 10
        if not profile_found: # Rescue points if DB query failed but UI shows it
            score += 20 
            feedback_parts.append("(VLM) Profile visible in UI.")
            
    if vlm_data.get('condition_correct'):
        vlm_score += 15
        feedback_parts.append("(VLM) Condition verified visually.")
        
    if vlm_data.get('email_visible'):
        vlm_score += 10
        if not email_configured:
            score += 10 # Rescue points
            feedback_parts.append("(VLM) Email configuration seen visually.")

    score += vlm_score

    # Cap score at 100
    score = min(100, score)
    
    passed = score >= 70 and (profile_found or vlm_data.get('profile_visible'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }