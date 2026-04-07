#!/usr/bin/env python3
"""
Verifier for validation_protocol_execution_nibp@1.

Verifies:
1. NIBP/Multiparameter device was created.
2. Vital Signs app was launched.
3. User waited for data (inferred from timestamps or file existence).
4. Evidence files (screenshot + text) exist and are valid.
5. Text file contains physiological values (Sys > Dia).
6. Clean shutdown (Vital Signs app is closed at the end).
"""

import json
import os
import re
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_validation_protocol_execution_nibp(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start = result.get("task_start", 0)
    device_created = result.get("device_created_log", False)
    app_launched = result.get("app_launched_log", False)
    
    screenshot_exists = result.get("screenshot_exists", False)
    screenshot_ts = result.get("screenshot_timestamp", 0)
    
    text_exists = result.get("text_file_exists", False)
    text_content = result.get("text_file_content", "")
    text_ts = result.get("text_timestamp", 0)
    
    vitals_window_open = result.get("vitals_window_still_open", False)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Device Created (20 pts)
    if device_created:
        score += 20
        feedback.append("NIBP/Multiparameter device created.")
    else:
        feedback.append("FAIL: No NIBP-capable device creation detected in logs.")

    # Criterion 2: App Launched (15 pts)
    if app_launched:
        score += 15
        feedback.append("Vital Signs app launched.")
    else:
        feedback.append("FAIL: Vital Signs app launch not detected.")

    # Criterion 3: Evidence Created (Screenshot) (15 pts)
    # Must be created AFTER task start
    if screenshot_exists and screenshot_ts > task_start:
        score += 15
        feedback.append("Evidence screenshot created.")
    else:
        feedback.append("FAIL: Evidence screenshot missing or stale.")

    # Criterion 4: Evidence Created (Text File) (15 pts)
    # Must be created AFTER task start
    if text_exists and text_ts > task_start:
        score += 15
        feedback.append("Evidence text file created.")
    else:
        feedback.append("FAIL: Evidence text file missing or stale.")

    # Criterion 5: Data Validity Check (15 pts)
    # Check regex for "Systolic: 120 mmHg, Diastolic: 80 mmHg" format
    # Allow some flexibility in spacing/case
    systolic = 0
    diastolic = 0
    valid_data = False
    
    # Regex to find systolic and diastolic values
    sys_match = re.search(r"Systolic[:\s]+(\d+)", text_content, re.IGNORECASE)
    dia_match = re.search(r"Diastolic[:\s]+(\d+)", text_content, re.IGNORECASE)
    
    if sys_match and dia_match:
        systolic = int(sys_match.group(1))
        diastolic = int(dia_match.group(1))
        
        # Check physiological plausibility (and that agent didn't just write 0/0)
        if 60 < systolic < 250 and 30 < diastolic < 150 and systolic > diastolic:
            valid_data = True
            score += 15
            feedback.append(f"Valid NIBP data recorded: {systolic}/{diastolic}.")
        else:
            feedback.append(f"FAIL: Recorded values implausible ({systolic}/{diastolic}).")
    else:
        if text_exists:
            feedback.append("FAIL: Text file format incorrect. Expected 'Systolic: X, Diastolic: Y'.")

    # Criterion 6: Clean Shutdown (20 pts)
    # Vital Signs window should NOT be open at the end
    # We only give points if they actually launched it first (don't reward doing nothing)
    if app_launched and not vitals_window_open:
        score += 20
        feedback.append("Clean shutdown: Vital Signs app closed successfully.")
    elif not app_launched:
        feedback.append("Shutdown check skipped (App never launched).")
    else:
        feedback.append("FAIL: Vital Signs app left open (Clean shutdown required).")

    # 4. Optional VLM Verification (Bonus/Confirmation)
    # If we have the screenshot, we could use VLM to verify numbers match text
    # For this strict protocol, regex is usually sufficient, but VLM adds robustness
    from gym_anything.vlm import query_vlm, get_final_screenshot
    
    # We want to check the evidence screenshot specifically if available, 
    # but the framework usually provides trajectory frames. 
    # We'll use the final state screenshot from export if available.
    
    pass_threshold = 65
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }