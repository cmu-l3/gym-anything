#!/usr/bin/env python3
"""
Verifier for Data Integrity Hardening task.

Checks:
1. Regex pattern on SUBJID (30 pts)
2. Min/Max limits on BP_SYS (20 pts)
3. Min/Max limits on BP_DIA (20 pts)
4. Validation equation on SCREEN_DATE (20 pts)
5. Validation tips/help text (10 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_integrity_hardening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result
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

    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey not found in database"}

    score = 0
    feedback = []

    # 1. Verify Regex (30 pts)
    # Expected: ^[A-Z]{3}-[0-9]{3}$ (or similar)
    regex_val = result.get("subjid", {}).get("regex", "")
    # Check for essential components: [A-Z]{3} and [0-9]{3} and hyphen
    if "[A-Z]{3}" in regex_val and "[0-9]{3}" in regex_val and "-" in regex_val:
        score += 30
        feedback.append("Subject ID Regex: Valid")
    else:
        feedback.append(f"Subject ID Regex: Invalid or missing (Got: '{regex_val}')")

    # 2. Verify BP_SYS Limits (20 pts)
    # Expected: Min 70, Max 220
    sys_min = result.get("bp_sys", {}).get("min")
    sys_max = result.get("bp_sys", {}).get("max")
    
    # Handle string/int types
    try:
        if int(sys_min) == 70 and int(sys_max) == 220:
            score += 20
            feedback.append("Systolic BP Limits: Correct")
        else:
            feedback.append(f"Systolic BP Limits: Incorrect (Got Min:{sys_min}, Max:{sys_max})")
    except (TypeError, ValueError):
        feedback.append(f"Systolic BP Limits: Missing or invalid format")

    # 3. Verify BP_DIA Limits (20 pts)
    # Expected: Min 40, Max 120
    dia_min = result.get("bp_dia", {}).get("min")
    dia_max = result.get("bp_dia", {}).get("max")
    
    try:
        if int(dia_min) == 40 and int(dia_max) == 120:
            score += 20
            feedback.append("Diastolic BP Limits: Correct")
        else:
            feedback.append(f"Diastolic BP Limits: Incorrect (Got Min:{dia_min}, Max:{dia_max})")
    except (TypeError, ValueError):
        feedback.append(f"Diastolic BP Limits: Missing or invalid format")

    # 4. Verify Date Logic (20 pts)
    # Expected: strtotime(self) <= strtotime('now') or similar
    eq = result.get("screen_date", {}).get("equation", "").replace(" ", "").lower()
    if "strtotime" in eq and ("<=" in eq or "<" in eq) and ("now" in eq or "date" in eq):
        score += 20
        feedback.append("Date Validation: Correct logic found")
    else:
        feedback.append(f"Date Validation: Logic missing or incorrect (Got: '{result.get('screen_date', {}).get('equation', '')}')")

    # 5. Verify Validation Tips (10 pts)
    # Check for help text in either subjid or date
    subj_help = result.get("subjid", {}).get("help_text", "").lower()
    date_help = result.get("screen_date", {}).get("help_text", "").lower()
    
    tips_found = 0
    if "format" in subj_help or "xxx" in subj_help:
        tips_found += 1
    if "future" in date_help:
        tips_found += 1
    
    if tips_found == 2:
        score += 10
        feedback.append("Validation Tips: All present")
    elif tips_found == 1:
        score += 5
        feedback.append("Validation Tips: Partially present")
    else:
        feedback.append("Validation Tips: Missing")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }