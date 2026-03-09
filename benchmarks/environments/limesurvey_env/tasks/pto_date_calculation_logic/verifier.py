#!/usr/bin/env python3
"""
Verifier for PTO Date Calculation Logic task.

Required Logic:
1. Survey 'PTO Request Form 2024' exists.
2. Question 'start' (Date) exists.
3. Question 'return' (Date) exists AND has validation logic ensuring return > start.
4. Question 'calc_days' (Equation) exists AND calculates date difference (strtotime/86400).
5. Question 'med_cert' (File) exists AND has relevance logic (calc_days > 3).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pto_date_logic(traj, env_info, task_info):
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

    # Basic Checks
    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'PTO Request Form 2024' not found."}

    questions = result.get("questions", [])
    q_map = {q['code']: q for q in questions}

    score = 0
    feedback = []

    # 1. Start Date Check (10 pts)
    if 'start' in q_map:
        q = q_map['start']
        # Type D is Date/Time
        if q['type'] == 'D':
            score += 10
            feedback.append("Start date question found.")
        else:
            score += 5
            feedback.append("Start date found but wrong type (expected Date).")
    else:
        feedback.append("Start date question ('start') missing.")

    # 2. Return Date & Validation (25 pts)
    if 'return' in q_map:
        q = q_map['return']
        validation = q.get('validation', '') or ''
        
        # Check if validation compares return and start
        # Logic: return > start OR start < return
        # Also strtotime might be used explicitly
        
        has_vars = 'start' in validation and 'return' in validation
        has_logic = '>' in validation or '<' in validation or 'gt' in validation.lower()
        
        if q['type'] == 'D' and has_vars and has_logic:
            score += 25
            feedback.append("Return date validation logic correct.")
        elif q['type'] == 'D':
            score += 10
            feedback.append("Return date found but validation logic missing or incorrect.")
        else:
            score += 5
            feedback.append("Return date found but wrong type.")
    else:
        feedback.append("Return date question ('return') missing.")

    # 3. Calculation Equation (30 pts)
    if 'calc_days' in q_map:
        q = q_map['calc_days']
        equation = q.get('question_text', '') or '' # For Equation type, text IS the equation
        
        # Check type (Equation type is usually '*')
        if q['type'] == '*':
            # Check for key calculation components
            has_strtotime = 'strtotime' in equation.lower()
            has_subtraction = '-' in equation
            has_division = '/' in equation and ('86400' in equation or '24' in equation) # 86400 is seconds in day
            
            if has_strtotime and has_subtraction and has_division:
                score += 30
                feedback.append("Duration calculation equation correct.")
            else:
                score += 15
                feedback.append(f"Duration equation found but logic seems incomplete (Found: {equation}).")
        else:
            feedback.append("Calculation question found but wrong type (expected Equation '*').")
    else:
        feedback.append("Calculation question ('calc_days') missing.")

    # 4. Relevance Logic (25 pts)
    if 'med_cert' in q_map:
        q = q_map['med_cert']
        relevance = q.get('relevance', '') or ''
        
        # Check Logic: calc_days > 3
        has_ref = 'calc_days' in relevance
        has_thresh = '3' in relevance
        has_op = '>' in relevance or 'gt' in relevance.lower()
        
        if q['type'] == '|' or True: # '|' is File Upload. Accepting True as type varies by version, logic is key.
             if has_ref and has_thresh and has_op:
                 score += 25
                 feedback.append("Medical certificate relevance logic correct.")
             else:
                 score += 10
                 feedback.append(f"Medical certificate question found but relevance logic incorrect (Found: {relevance}).")
    else:
        feedback.append("Medical certificate question ('med_cert') missing.")

    # 5. Active Status (10 pts)
    active = result.get("active", "N")
    if active == "Y":
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }