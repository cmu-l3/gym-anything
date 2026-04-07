#!/usr/bin/env python3
"""
verifier.py — Alarm Escalation Rules Configuration

Scoring (100 pts total, pass threshold 60):
  - Rule 1 (Critical-Immediate-Escalation): Exists (15 pts), Email Correct (10 pts)
  - Rule 2 (Major-Triage-Escalation):       Exists (15 pts), Email Correct (10 pts)
  - Rule 3 (DeviceDown-Emergency-Escalation): Exists (15 pts), Email Correct (10 pts)
  - Rule 4 (Warning-Review-Escalation):     Exists (15 pts), Email Correct (10 pts)
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define the target rules from the policy document
TARGET_RULES = [
    {
        "name": "Critical-Immediate-Escalation",
        "email": "soc-critical@msp-ops.internal"
    },
    {
        "name": "Major-Triage-Escalation",
        "email": "noc-triage@msp-ops.internal"
    },
    {
        "name": "DeviceDown-Emergency-Escalation",
        "email": "emergency-response@msp-ops.internal"
    },
    {
        "name": "Warning-Review-Escalation",
        "email": "ops-review@msp-ops.internal"
    }
]


def _check_presence(combined_text, target):
    """Simple case-insensitive substring check."""
    return target.lower() in combined_text


def _check_proximity(combined_text, name, email):
    """
    Check if the email appears within a reasonable proximity window (2000 chars)
    of the rule name, to prevent matching unrelated entries in a large DB dump.
    """
    lower_text = combined_text
    lower_name = name.lower()
    lower_email = email.lower()

    idx = lower_text.find(lower_name)
    if idx == -1:
        return False

    # Check the window around the first occurrence
    window_start = max(0, idx - 2000)
    window_end = min(len(lower_text), idx + len(lower_name) + 2000)
    window = lower_text[window_start:window_end]

    if lower_email in window:
        return True
    
    # If not found around the first occurrence, search iteratively in case there are multiple
    search_idx = 0
    while True:
        idx = lower_text.find(lower_name, search_idx)
        if idx == -1:
            break
        window_start = max(0, idx - 2000)
        window_end = min(len(lower_text), idx + len(lower_name) + 2000)
        window = lower_text[window_start:window_end]
        if lower_email in window:
            return True
        search_idx = idx + len(lower_name)

    return False


def verify_alarm_escalation_rules_config(traj, env_info, task_info):
    """Main verification function."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/alarm_escalation_result.json')
    local_path = '/tmp/alarm_escalation_verify_result.json'

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from container: {e}. Check if export script failed."
        }

    try:
        with open(local_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse JSON result: {e}"
        }

    # Combine API data and DB dump into a single lowercase searchable text block
    api_text = json.dumps(data.get("api_data", {})).lower()
    db_raw = data.get("db_raw", "").lower()
    combined_text = api_text + "\n" + db_raw

    score = 0
    feedback_parts = []
    
    # Check each rule
    for idx, rule in enumerate(TARGET_RULES, 1):
        name = rule["name"]
        email = rule["email"]
        
        name_exists = _check_presence(combined_text, name)
        email_correct = False
        
        if name_exists:
            score += 15
            email_correct = _check_proximity(combined_text, name, email)
            if email_correct:
                score += 10
                feedback_parts.append(f"PASS: Rule {idx} '{name}' found with correct email (+25)")
            else:
                feedback_parts.append(f"PARTIAL: Rule {idx} '{name}' found, but email '{email}' is missing or incorrect (+15)")
        else:
            feedback_parts.append(f"FAIL: Rule {idx} '{name}' not found in DB/API (0/25)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }