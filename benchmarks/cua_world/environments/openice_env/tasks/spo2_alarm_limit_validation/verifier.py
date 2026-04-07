#!/usr/bin/env python3
"""Verifier for spo2_alarm_limit_validation task in OpenICE."""

import json
import tempfile
import os
import shutil

def verify_spo2_alarm_limit_validation(traj, env_info, task_info):
    """
    Verify the SpO2 alarm limit validation task.
    
    Criteria:
    1. Simulated Pulse Oximeter created (15 pts)
    2. Alarm List application launched (15 pts)
    3. Evidence screenshot exists (30 pts)
    4. Report exists and is valid JSON (10 pts)
    5. Reported threshold is within realistic range (80-95) (30 pts)
    
    Total: 100 pts. Pass threshold: 70 pts.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_min_threshold', 80)
    expected_max = metadata.get('expected_max_threshold', 95)

    # Read result JSON
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
    
    # 1. Device Creation (15 pts)
    if result.get('pulse_oximeter_created', False):
        score += 15
        feedback_parts.append("Pulse Oximeter created")
    else:
        feedback_parts.append("Pulse Oximeter NOT created")

    # 2. App Launch (15 pts)
    if result.get('alarm_app_launched', False):
        score += 15
        feedback_parts.append("Alarm List app launched")
    else:
        feedback_parts.append("Alarm List app NOT launched")

    # 3. Evidence Screenshot (30 pts)
    if result.get('evidence_screenshot_exists', False):
        size = result.get('evidence_screenshot_size', 0)
        if size > 1000: # minimal check for non-empty file
            score += 30
            feedback_parts.append("Evidence screenshot captured")
        else:
            feedback_parts.append("Evidence screenshot empty/invalid")
    else:
        feedback_parts.append("Evidence screenshot missing")

    # 4. Report Structure (10 pts)
    if result.get('report_exists', False) and result.get('report_valid_json', False):
        score += 10
        feedback_parts.append("Valid JSON report found")
    else:
        feedback_parts.append("Report missing or invalid JSON")

    # 5. Threshold Accuracy (30 pts)
    reported_val = result.get('reported_threshold', -1)
    
    # Handle string inputs gracefully if they slipped through
    try:
        val = int(reported_val)
    except:
        val = -1

    if expected_min <= val <= expected_max:
        score += 30
        feedback_parts.append(f"Threshold value {val} is correct")
    elif val != -1:
        feedback_parts.append(f"Threshold value {val} is out of expected range ({expected_min}-{expected_max})")
    else:
        feedback_parts.append("Threshold value not found in report")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }