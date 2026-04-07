#!/usr/bin/env python3
"""
Verifier for configure_database_backup task.

Task Requirements:
1. Enable Scheduled DB Backup
2. Frequency: Daily
3. Time: 02:00
4. Path: C:\\ADAuditBackups
5. Retention: 30

Verification Strategy:
1. Programmatic: Check if configuration files were modified (anti-gaming: did they actually change settings?)
2. Programmatic: Check if the target backup directory exists (weak signal, but necessary condition)
3. VLM: Visual verification of the settings page to confirm specific values (Primary signal for web config)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_database_backup(traj, env_info, task_info):
    """
    Verifies the agent correctly configured the database backup settings.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Programmatic Checks (30 Points)
    
    # Criterion A: Configuration was modified (15 pts)
    # This prevents 'do nothing' agents or agents that just navigate without saving
    if result_data.get('config_modified', False):
        score += 15
        feedback.append("Configuration files updated.")
    else:
        feedback.append("No configuration changes detected.")

    # Criterion B: Backup Directory Exists (15 pts)
    # The path 'C:\ADAuditBackups' should exist if configured correctly (or created by agent)
    if result_data.get('backup_dir_exists', False):
        score += 15
        feedback.append("Target backup directory exists.")
    else:
        feedback.append("Target backup directory C:\\ADAuditBackups not found.")

    # 3. VLM Verification (70 Points)
    # We need to verify the specific values in the UI since parsing the proprietary config files 
    # might be unreliable or encryption-dependent.
    
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Construct VLM Prompt
    # We ask the VLM to look for the specific form fields
    prompt = """
    You are auditing a software configuration task for ManageEngine ADAudit Plus.
    The agent was asked to configure 'Scheduled DB Backup' with specific settings.
    
    Review the screenshots, specifically the final configuration state.
    
    Check for these EXACT settings:
    1. "Scheduled DB Backup" (or similar toggle) is ENABLED/CHECKED.
    2. "Backup Frequency" (or Schedule) is set to "Daily".
    3. "Time" is set to "02:00" or "02:00 AM".
    4. "Backup Storage Path" contains "C:\\ADAuditBackups".
    5. "Maintain the last" (Retention) is set to "30" count/days.
    
    Return a JSON object with boolean status for each:
    {
        "backup_enabled": true/false,
        "frequency_daily": true/false,
        "time_0200": true/false,
        "path_correct": true/false,
        "retention_30": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    # Use the final screenshot primarily, but provide context frames if needed
    vlm_response = query_vlm(images=[final_shot], prompt=prompt)
    
    if not vlm_response.get('success'):
        feedback.append("VLM verification failed to process images.")
        # Fallback: if programmatic checks passed, give partial credit? 
        # No, for settings tasks, UI verification is critical.
    else:
        parsed = vlm_response.get('parsed', {})
        
        # Scoring based on VLM findings
        # 1. Enabled (15 pts)
        if parsed.get('backup_enabled'):
            score += 15
            feedback.append("VLM: Backup enabled.")
        else:
            feedback.append("VLM: Backup NOT enabled.")

        # 2. Path Correct (15 pts)
        if parsed.get('path_correct'):
            score += 15
            feedback.append("VLM: Path set correctly.")
        else:
            feedback.append("VLM: Path incorrect.")

        # 3. Time Correct (15 pts)
        if parsed.get('time_0200'):
            score += 15
            feedback.append("VLM: Time set to 02:00.")
        else:
            feedback.append("VLM: Time incorrect.")

        # 4. Retention Correct (15 pts)
        if parsed.get('retention_30'):
            score += 15
            feedback.append("VLM: Retention set to 30.")
        else:
            feedback.append("VLM: Retention incorrect.")

        # 5. Frequency (10 pts)
        if parsed.get('frequency_daily'):
            score += 10
            feedback.append("VLM: Frequency set to Daily.")
        else:
            feedback.append("VLM: Frequency incorrect.")

    # 4. Final Evaluation
    # Max Score = 30 (Programmatic) + 70 (VLM) = 100
    # Pass Threshold = 60
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }