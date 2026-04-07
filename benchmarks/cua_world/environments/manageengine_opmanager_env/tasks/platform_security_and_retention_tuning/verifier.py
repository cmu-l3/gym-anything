#!/usr/bin/env python3
"""
verifier.py — Platform Security and Retention Tuning

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Detailed Data Retention = 8  — 10 pts
  Criterion 2: Hourly Data Retention = 35  — 10 pts
  Criterion 3: Daily Data Retention = 190  — 15 pts
  Criterion 4: Alarms (45) & Events (25) Retention — 15 pts
  Criterion 5: Syslog/Traps Retention = 12 — 10 pts
  Criterion 6: Session Timeout = 12       — 40 pts
"""

import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_value_near_keywords(text, value_str, keywords, window=250):
    """
    Finds exact whole-number matches of value_str in text, and checks if
    any keyword appears within `window` characters before or after it.
    """
    text_lower = text.lower()
    val = str(value_str)
    
    # regex for exact number (not preceded or followed by digits)
    pattern = r'(?<!\d)' + re.escape(val) + r'(?!\d)'
    
    for match in re.finditer(pattern, text_lower):
        start = max(0, match.start() - window)
        end = min(len(text_lower), match.end() + window)
        context = text_lower[start:end]
        
        for kw in keywords:
            if kw.lower() in context:
                return True
    return False

def verify_platform_security_and_retention_tuning(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/platform_tuning_result.json')
    local_path = '/tmp/platform_tuning_verify_result.json'

    if 'copy_from_env' not in env_info:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check export_result.sh."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    # Combine all API JSONs and raw DB output into one searchable string
    combined_text = json.dumps(data).lower()

    score = 0
    details = []

    # 1. Detailed: 8
    if check_value_near_keywords(combined_text, "8", ["detail", "raw", "data"]):
        score += 10
        details.append("PASS: Detailed Data Retention set to 8 (+10)")
    else:
        details.append("FAIL: Detailed Data Retention not set to 8 (0/10)")

    # 2. Hourly: 35
    if check_value_near_keywords(combined_text, "35", ["hour"]):
        score += 10
        details.append("PASS: Hourly Data Retention set to 35 (+10)")
    else:
        details.append("FAIL: Hourly Data Retention not set to 35 (0/10)")

    # 3. Daily: 190
    if check_value_near_keywords(combined_text, "190", ["dail"]):
        score += 15
        details.append("PASS: Daily Data Retention set to 190 (+15)")
    else:
        details.append("FAIL: Daily Data Retention not set to 190 (0/15)")

    # 4. Alarms (45) & Events (25)
    alarms = check_value_near_keywords(combined_text, "45", ["alarm"])
    events = check_value_near_keywords(combined_text, "25", ["event"])
    if alarms and events:
        score += 15
        details.append("PASS: Alarms and Events Retention set correctly (+15)")
    else:
        details.append("FAIL: Alarms or Events Retention incorrect (0/15)")

    # 5. Syslog: 12
    if check_value_near_keywords(combined_text, "12", ["syslog", "trap"]):
        score += 10
        details.append("PASS: Syslog/Traps Retention set to 12 (+10)")
    else:
        details.append("FAIL: Syslog/Traps Retention not set to 12 (0/10)")

    # 6. Session Timeout: 12
    # Ensure it's near session timeout keywords to differentiate from Syslog 12
    if check_value_near_keywords(combined_text, "12", ["session", "timeout", "expir"]):
        score += 40
        details.append("PASS: Session Timeout set to 12 (+40)")
    else:
        details.append("FAIL: Session Timeout not set to 12 (0/40)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }