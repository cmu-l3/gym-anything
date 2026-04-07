#!/usr/bin/env python3
"""
Verifier for analyze_offline_incident_data task.

Verification Logic:
1. Validates that the agent's output JSON matches the ground truth generated at setup.
2. Checks for:
   - Correct Attacker IP (Exact match)
   - Correct Compromised User (Exact match)
   - Correct Timestamps (Exact match expected, as they come from logs)
   - Correct Time-to-Compromise calculation (within tolerance)
3. Anti-gaming: Ensures the file was created during the task session.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_offline_incident_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve the result file (which contains both submission and ground truth)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Basic Checks ---
    if not result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file ~/incident_report.json not found."
        }
        
    if not result.get("created_during_task", True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was not created/modified during the task session."
        }

    submission = result.get("submission", {})
    truth = result.get("ground_truth", {})
    
    if not submission or not truth:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Submission or ground truth data is empty/invalid JSON."
        }

    score = 0
    feedback_parts = []
    
    # --- 1. Attacker IP (25 pts) ---
    sub_ip = submission.get("attacker_ip", "").strip()
    truth_ip = truth.get("attacker_ip", "")
    if sub_ip == truth_ip:
        score += 25
        feedback_parts.append(f"Attacker IP correct ({sub_ip})")
    else:
        feedback_parts.append(f"Attacker IP incorrect (Expected: {truth_ip}, Got: {sub_ip})")

    # --- 2. Compromised User (25 pts) ---
    sub_user = submission.get("compromised_user", "").strip()
    truth_user = truth.get("compromised_user", "")
    if sub_user == truth_user:
        score += 25
        feedback_parts.append(f"Compromised user correct ({sub_user})")
    else:
        feedback_parts.append(f"Compromised user incorrect (Expected: {truth_user}, Got: {sub_user})")

    # --- 3. Timestamps (25 pts) ---
    # We check string equality because the task asks to extract them exactly
    sub_start = submission.get("attack_start_timestamp", "").strip()
    truth_start = truth.get("attack_start_timestamp", "")
    
    sub_end = submission.get("compromise_timestamp", "").strip()
    truth_end = truth.get("compromise_timestamp", "")
    
    ts_score = 0
    if sub_start == truth_start:
        ts_score += 12.5
    else:
        feedback_parts.append(f"Start timestamp mismatch (Expected: {truth_start}, Got: {sub_start})")
        
    if sub_end == truth_end:
        ts_score += 12.5
    else:
        feedback_parts.append(f"Compromise timestamp mismatch (Expected: {truth_end}, Got: {sub_end})")
    
    if ts_score == 25:
        feedback_parts.append("Timestamps correct")
    score += ts_score

    # --- 4. Metric Calculation (25 pts) ---
    try:
        sub_calc = int(submission.get("time_to_compromise_seconds", -999))
        truth_calc = int(truth.get("time_to_compromise_seconds", 0))
        
        # Allow +/- 1 second tolerance for calculation rounding
        if abs(sub_calc - truth_calc) <= 1:
            score += 25
            feedback_parts.append(f"Time calculation correct ({sub_calc}s)")
        else:
            feedback_parts.append(f"Time calculation incorrect (Expected: {truth_calc}, Got: {sub_calc})")
    except (ValueError, TypeError):
        feedback_parts.append("Time calculation invalid (not an integer)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }