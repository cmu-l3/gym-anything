#!/usr/bin/env python3
"""
Verifier for prefilled_hidden_data_config@1

Criteria:
1. Survey exists (Gate)
2. Tokens initialized & attributes created (20 pts)
3. Participant Elena Rossi added with correct data (10 pts)
4. Hidden questions 'sys_dept' and 'sys_role' exist (20 pts)
5. Questions are actually hidden (20 pts)
6. Correct Expression Manager syntax used for defaults (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prefilled_hidden_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
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
    feedback = []
    
    # 1. Survey Check
    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey '2025 Employee Engagement Pulse' not found."}
    
    feedback.append("Survey found.")

    # 2. Tokens & Attributes (20 pts)
    if result.get("tokens_table_exists") and result.get("attributes_created"):
        score += 20
        feedback.append("Tokens initialized and attributes created.")
    else:
        feedback.append("Tokens not initialized or attributes missing.")

    # 3. Participant Data (10 pts)
    if result.get("participant_found"):
        score += 10
        feedback.append("Participant Elena Rossi found.")
    else:
        feedback.append("Participant Elena Rossi not found.")

    # 4. Questions Exist (20 pts)
    if result.get("questions_found"):
        score += 20
        feedback.append("Target questions (sys_dept, sys_role) found.")
    else:
        feedback.append("Target questions missing.")

    # 5. Hidden Config (20 pts)
    if result.get("hidden_config_correct"):
        score += 20
        feedback.append("Questions are correctly set to Hidden.")
    elif result.get("questions_found"):
        feedback.append("Questions exist but 'Always hide this question' is not set.")

    # 6. Syntax Check (30 pts)
    # Flexible matching for syntax: {TOKEN:ATTRIBUTE_1} or {TOKEN:ATTRIBUTE_2}
    # LimeSurvey might store it with uppercase/lowercase or spacing, though usually exact.
    dept_val = result.get("dept_default_value", "").upper()
    role_val = result.get("role_default_value", "").upper()
    
    syntax_score = 0
    
    # Dept syntax
    if "{TOKEN:ATTRIBUTE_1}" in dept_val:
        syntax_score += 15
    elif "ATTRIBUTE_1" in dept_val:
        # Partial credit if syntax is close but slightly wrong (e.g. missing curly braces)
        syntax_score += 5 
        feedback.append(f"Dept syntax close but incorrect: {dept_val}")

    # Role syntax
    if "{TOKEN:ATTRIBUTE_2}" in role_val:
        syntax_score += 15
    elif "ATTRIBUTE_2" in role_val:
        syntax_score += 5
        feedback.append(f"Role syntax close but incorrect: {role_val}")
        
    if syntax_score == 30:
        feedback.append("Expression Manager syntax correct for both defaults.")
    elif syntax_score > 0:
        feedback.append("Partial credit for default value syntax.")
    else:
        feedback.append("Default values missing or incorrect.")
        
    score += syntax_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }