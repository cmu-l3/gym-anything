#!/usr/bin/env python3
"""
verifier.py — Monitoring Platform Disaster Recovery Setup

Verification Strategy (Multi-Signal):
1. OS Level: Directory exists (15 points)
2. OS Level: Directory has exact '750' permissions (15 points)
3. App Level (DB/API): Destination path configured in OpManager (20 points)
4. App Level (DB/API): Retention is 14 days (10 points)
5. App Level (DB/API): Schedule time is 01:30 AM (10 points)
6. VLM Level: Agent interacted with the UI Backup settings form (30 points)

Threshold: 60 points, requiring basic directory creation + destination mapping.
"""

import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_monitoring_platform_disaster_recovery_setup(traj, env_info, task_info):
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/dr_setup_result.json")
    local_path = "/tmp/dr_setup_verify.json"
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    try:
        copy_from_env(result_file, local_path)
        with open(local_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse result file: {e}"
        }

    score = 0
    feedback_parts = []
    
    # Extract OS details
    dir_exists = data.get("dir_exists") == "true"
    dir_perms = data.get("dir_perms", "")
    
    # Extract DB/API details
    db_raw = data.get("db_raw", "").lower()
    api_raw = json.dumps(data.get("api_raw", {})).lower()
    combined_text = db_raw + "\n" + api_raw

    # Expected Values
    expected_dir = "var/opt/opmanager_backups" # Use relative path to avoid JSON escaping issues
    expected_retention = "14"
    
    # ==========================================
    # 1 & 2. OS Level Checks (30 points total)
    # ==========================================
    if dir_exists:
        score += 15
        feedback_parts.append("PASS: Target backup directory created (+15).")
        
        if dir_perms == "750":
            score += 15
            feedback_parts.append("PASS: Directory permissions strictly match '750' (+15).")
        else:
            feedback_parts.append(f"FAIL: Directory permissions are '{dir_perms}', expected '750' (+0).")
    else:
        feedback_parts.append("FAIL: Target backup directory was not created (+0).")

    # ==========================================
    # 3. App Level: Destination Mapping (20 points)
    # ==========================================
    dest_mapped = expected_dir in combined_text
    if dest_mapped:
        score += 20
        feedback_parts.append("PASS: Backup destination mapped in OpManager configuration (+20).")
    else:
        feedback_parts.append("FAIL: Backup destination not found in OpManager DB/API (+0).")

    # ==========================================
    # 4 & 5. App Level: Retention and Time (20 points total)
    # Only check if destination is mapped, using proximity to avoid false positives
    # ==========================================
    if dest_mapped:
        idx = combined_text.find(expected_dir)
        window_start = max(0, idx - 1500)
        window_end = min(len(combined_text), idx + 1500)
        proximity_window = combined_text[window_start:window_end]

        # Retention Check
        if expected_retention in proximity_window:
            score += 10
            feedback_parts.append("PASS: Retention policy of 14 days found (+10).")
        else:
            feedback_parts.append("FAIL: Retention policy of 14 days not found in configuration window (+0).")
            
        # Time Check (Lenient on exact format: 01:30, 1:30, or CRON components)
        time_pattern = re.compile(r'(0?1:30|1:30\s*am|30\s+1\s)')
        if time_pattern.search(proximity_window):
            score += 10
            feedback_parts.append("PASS: Scheduled time 01:30 found (+10).")
        elif "1" in proximity_window and "30" in proximity_window:
            # Partial credit if components are found (e.g., separate hour/minute DB columns)
            score += 5
            feedback_parts.append("PARTIAL: Hour '1' and minute '30' components found (+5).")
        else:
            feedback_parts.append("FAIL: Scheduled time 01:30 not found (+0).")
    else:
        feedback_parts.append("FAIL: Schedule details skipped because destination wasn't mapped (+0).")

    # ==========================================
    # 6. VLM Trajectory Check (30 points)
    # ==========================================
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory to ensure the agent didn't just curl the API
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            vlm_prompt = """
            You are verifying an IT administrator's workflow in ManageEngine OpManager.
            The user was tasked with enabling and configuring Database Backups.
            
            Examine the provided trajectory images and determine if:
            1. The agent navigated to the 'Database Backup' or 'Schedule Backup' configuration page in the UI.
            2. The agent interacted with the form (e.g., entered the path '/var/opt/opmanager_backups', frequency, or retention).
            
            Respond strictly in JSON format:
            {
                "interacted_with_backup_ui": true or false,
                "reasoning": "brief explanation"
            }
            """
            
            vlm_result = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("interacted_with_backup_ui", False):
                    score += 30
                    feedback_parts.append("PASS: VLM verified active UI interaction with the Backup settings (+30).")
                else:
                    feedback_parts.append("FAIL: VLM did not detect interaction with the UI Backup settings form (+0).")
            else:
                feedback_parts.append("WARNING: VLM query returned unsuccessful result.")
                
        except Exception as e:
            logger.warning(f"VLM Trajectory verification failed: {e}")
            feedback_parts.append(f"WARNING: VLM processing error: {e}")

    # Final logic
    key_criteria_met = dir_exists and dest_mapped
    passed = (score >= 60) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS: Core DR requirements met.")
    else:
        feedback_parts.insert(0, "FAILURE: Minimum DR requirements not met (need Directory + App Destination).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }