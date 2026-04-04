#!/usr/bin/env python3
"""
Verifier for safety_induction_assessment_rules task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safety_induction(traj, env_info, task_info):
    """
    Verify the configuration of the Safety Induction Exam.
    
    Criteria:
    1. Assessments mode enabled (10 pts)
    2. Correct Assessment Values assigned to answers (40 pts)
    3. Fail/Pass Rules configured correctly (40 pts)
    4. Survey Active (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'Site Safety Induction Exam 2024' not found."}

    score = 0
    feedback = []

    # 1. Check Assessments Enabled (10 pts)
    if result.get("assessments_enabled") == "Y":
        score += 10
        feedback.append("Assessments mode enabled.")
    else:
        feedback.append("Assessments mode NOT enabled.")

    # 2. Check Answer Values (40 pts)
    # Define expected mappings (Keyword in Answer -> Expected Value)
    # We use keywords to be robust against minor typos in full text
    expected_values = {
        "Red": 1,
        "Yellow": 0,
        "Orange": 0,
        "6 feet": 1,
        "4 feet": 0,
        "10 feet": 0,
        "Everyone": 1,
        "Foreman": 0,
        "Safety Officer": 0,
        "Tag": 1, # Tag it
        "Use it": 0,
        "Leave it": 0
    }
    
    answers = result.get("answers", [])
    correct_configs = 0
    total_checks = 0
    
    for keyword, exp_val in expected_values.items():
        # Find matching answer in DB dump
        match = next((a for a in answers if keyword.lower() in a.get("answer", "").lower()), None)
        if match:
            total_checks += 1
            try:
                actual_val = int(match.get("value", -1))
                if actual_val == exp_val:
                    correct_configs += 1
                else:
                    feedback.append(f"Wrong value for '{keyword}': Expected {exp_val}, got {actual_val}")
            except ValueError:
                 feedback.append(f"Invalid value for '{keyword}'")
        else:
            feedback.append(f"Answer option containing '{keyword}' not found.")

    # Scaling score: 40 points distributed across the checkable items found
    # If 12 items expected, each is worth ~3.3 pts.
    if total_checks > 0:
        val_score = (correct_configs / len(expected_values)) * 40
        score += val_score
    
    if correct_configs == len(expected_values):
        feedback.append("All answer values configured correctly.")

    # 3. Check Rules (40 pts)
    rules = result.get("rules", [])
    fail_rule = False
    pass_rule = False

    for r in rules:
        try:
            r_min = float(r.get("min", -1))
            r_max = float(r.get("max", -1))
            msg = r.get("message", "").lower()
            
            # Check Fail Rule (0-3)
            if r_min == 0 and r_max == 3 and "fail" in msg:
                fail_rule = True
            
            # Check Pass Rule (4-4)
            if r_min == 4 and r_max == 4 and "pass" in msg:
                pass_rule = True
        except ValueError:
            continue

    if fail_rule:
        score += 20
        feedback.append("Fail rule (0-3) configured correctly.")
    else:
        feedback.append("Fail rule missing or incorrect range/message.")

    if pass_rule:
        score += 20
        feedback.append("Pass rule (4-4) configured correctly.")
    else:
        feedback.append("Pass rule missing or incorrect range/message.")

    # 4. Check Active (10 pts)
    if result.get("active") == "Y":
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    final_score = min(100, int(score))
    passed = final_score >= 80

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }