#!/usr/bin/env python3
"""
Verifier for dynamic_email_routing_config task.
Checks if the LimeSurvey 'email_admin_responses' field contains a valid Expression Manager formula.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dynamic_email_routing_config(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_critical = metadata.get('email_critical', 'pager@example.com')
    expected_standard = metadata.get('email_standard', 'tickets@example.com')
    question_code = metadata.get('question_code', 'Severity')
    condition_val = metadata.get('condition_value', 'L1')

    # Load Result
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

    # Basic Checks
    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'IT Incident Report Form 2025' not found in database."}

    raw_setting = result.get("admin_email_setting", "").strip()
    if not raw_setting:
        return {"passed": False, "score": 0, "feedback": "Detailed admin notification field is empty."}

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Syntax Check (40 pts)
    # Must start with {if( and end with )}
    # Allow whitespace flexibility
    normalized_setting = raw_setting.replace(" ", "")
    if normalized_setting.startswith("{if(") and normalized_setting.endswith(")}"):
        score += 40
        feedback.append("Valid Expression Manager syntax used.")
    else:
        feedback.append("Invalid syntax: Must use {if(...)} format.")

    # 2. Condition Check (30 pts)
    # Check for Severity=="L1" or Severity=='L1'
    # Quotes might be escaped or not, so we check flexible patterns
    # Regex look for: Severity followed by == or eq, then L1 in quotes
    condition_pattern = re.compile(rf"{question_code}\s*(==|eq)\s*['\"]{condition_val}['\"]", re.IGNORECASE)
    
    if condition_pattern.search(raw_setting):
        score += 30
        feedback.append("Condition logic matches expected criteria.")
    else:
        # Fallback check for normalized string
        if f"{question_code}==\"{condition_val}\"" in normalized_setting or \
           f"{question_code}=='{condition_val}'" in normalized_setting:
            score += 30
            feedback.append("Condition logic matches (fallback check).")
        else:
            feedback.append(f"Condition incorrect. Expected checks for {question_code} == '{condition_val}'.")

    # 3. Routing Addresses Check (30 pts)
    # Must contain both emails in correct order
    # pager@example.com first (True case), tickets@example.com second (False case)
    if expected_critical in raw_setting and expected_standard in raw_setting:
        idx_crit = raw_setting.find(expected_critical)
        idx_std = raw_setting.find(expected_standard)
        
        if idx_crit < idx_std:
            score += 30
            feedback.append("Email routing destinations are correct and in proper order.")
        else:
            score += 10 # Partial credit for having addresses but wrong order
            feedback.append("Emails present but order is reversed. 'True' condition should come first.")
    else:
        feedback.append("One or more required email addresses are missing.")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {"raw_setting": raw_setting}
    }