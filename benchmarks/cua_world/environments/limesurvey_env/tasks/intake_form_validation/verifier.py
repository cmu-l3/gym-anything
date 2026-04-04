#!/usr/bin/env python3
"""
Verifier for intake_form_validation task in LimeSurvey.
"""

import json
import tempfile
import os
import re

def verify_intake_form(traj, env_info, task_info):
    """
    Verify that the intake form was created with specific validation rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # ---------------------------------------------------------
    # SCORING LOGIC
    # ---------------------------------------------------------
    score = 0
    feedback = []
    
    # Gate Check: Survey Exists
    if not result.get('survey_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey titled 'CARDIA...' not found."
        }
    
    # 1. Basic Structure (20 pts)
    # 2 Groups (10 pts)
    g_count = int(result.get('group_count', 0))
    if g_count == 2:
        score += 10
        feedback.append("Correct group count (2).")
    else:
        feedback.append(f"Incorrect group count: {g_count} (expected 2).")

    # 7 Questions (10 pts)
    q_count = int(result.get('question_count', 0))
    if q_count == 7:
        score += 10
        feedback.append("Correct question count (7).")
    else:
        feedback.append(f"Incorrect question count: {q_count} (expected 7).")

    # 2. Activation (15 pts)
    if result.get('active') == 'Y':
        score += 15
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # 3. Question Validation Checks (55 pts)
    questions = result.get('questions', [])
    q_map = {q['code'].lower(): q for q in questions}

    # mandatory count check (10 pts)
    mandatory_count = sum(1 for q in questions if q.get('mandatory') == 'Y')
    if mandatory_count >= 6:
        score += 10
        feedback.append(f"Mandatory fields check passed ({mandatory_count}/7).")
    else:
        feedback.append(f"Too few mandatory fields: {mandatory_count} (expected >= 6).")

    # Check Age (15 pts) - Min 18, Max 99
    age_q = q_map.get('age')
    if age_q:
        attrs = age_q.get('attributes', {})
        min_val = attrs.get('min_num_value_n', '')
        max_val = attrs.get('max_num_value_n', '')
        if str(min_val) == '18' and str(max_val) == '99':
            score += 15
            feedback.append("Age validation correct (18-99).")
        else:
            feedback.append(f"Age validation incorrect (found min={min_val}, max={max_val}).")
    else:
        feedback.append("Question 'age' not found.")

    # Check Zipcode (15 pts) - Regex 5 digits
    zip_q = q_map.get('zipcode')
    if zip_q:
        attrs = zip_q.get('attributes', {})
        # Regex can be in em_validation_q or preg_validation depending on setup
        regex = attrs.get('em_validation_q', '') + attrs.get('preg_validation', '')
        # Check for 5 digit pattern loosely
        if '5' in regex and ('d' in regex or '0-9' in regex):
            score += 15
            feedback.append("Zipcode regex validation found.")
        else:
            feedback.append(f"Zipcode regex missing or incorrect (found '{regex}').")
    else:
        feedback.append("Question 'zipcode' not found.")

    # Check Email (15 pts) - Email validation logic
    email_q = q_map.get('email')
    if email_q:
        attrs = email_q.get('attributes', {})
        # Look for built-in email valid attribute usually handled by input type or regex
        # In LS DB, often stored as 'em_validation_q' containing 'email' or regex
        val_q = attrs.get('em_validation_q', '').lower()
        if 'email' in val_q or '@' in val_q:
             score += 15
             feedback.append("Email validation found.")
        # Alternatively check for input type specific attributes if applicable
        else:
             feedback.append("Email validation missing.")
    else:
        feedback.append("Question 'email' not found.")

    # Check Income (10 pts) - Min 0, Max 10000000
    income_q = q_map.get('income')
    if income_q:
        attrs = income_q.get('attributes', {})
        min_val = attrs.get('min_num_value_n', '')
        max_val = attrs.get('max_num_value_n', '')
        if str(min_val) == '0' and str(max_val) == '10000000':
            score += 10
            feedback.append("Income validation correct.")
        else:
            feedback.append(f"Income validation incorrect (found min={min_val}, max={max_val}).")
    else:
        feedback.append("Question 'income' not found.")

    # Final tally
    # Total possible: 10+10+15+10+15+15+15+10 = 100
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }