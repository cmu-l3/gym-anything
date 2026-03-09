#!/usr/bin/env python3
"""
Verifier for broken_logic_survey_troubleshooting task.

The agent must fix 3 logic errors in LimeSurvey:
1. Group 'Remote Work Tools': Incorrect variable name 'work_style' -> 'work_mode'
2. Question 'Q_Sales': Syntax error, unclosed quote '"SALES' -> '"SALES"'
3. Question 'Q_Shift': Logical error, assignment '=' -> comparison '=='
"""

import json
import os
import tempfile
import re

def verify_broken_logic_survey_troubleshooting(traj, env_info, task_info):
    # Use copy_from_env to retrieve the result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    group_logic = result.get("group_relevance", "")
    q_sales_logic = result.get("q_sales_relevance", "")
    q_shift_logic = result.get("q_shift_relevance", "")

    score = 0
    feedback = []

    # Criteria 1: Fix Group Logic (Variable Typo)
    # Original: work_style.NAOK == "Hybrid" ...
    # Correct: work_mode.NAOK == "Hybrid" ...
    # We check if 'work_mode' is present and 'work_style' is absent.
    c1_passed = False
    if "work_mode" in group_logic and "work_style" not in group_logic:
        score += 35
        c1_passed = True
        feedback.append("Group logic fixed (variable name corrected).")
    elif "work_mode" in group_logic:
        # Partial credit if they added the right one but left the wrong one? Unlikely in logic.
        score += 15
        feedback.append("Group logic references correct variable, but might still contain errors.")
    else:
        feedback.append(f"Group logic incorrect. Expected 'work_mode', found: '{group_logic}'")

    # Criteria 2: Fix Q_Sales Logic (Syntax/Quote)
    # Original: dep_code.NAOK == "SALES
    # Correct: dep_code.NAOK == "SALES"
    # We check for the presence of the closed string "SALES"
    c2_passed = False
    if '"SALES"' in q_sales_logic or "'SALES'" in q_sales_logic:
        score += 35
        c2_passed = True
        feedback.append("Q_Sales logic fixed (quote closed).")
    else:
        feedback.append(f"Q_Sales logic syntax incorrect. Expected '\"SALES\"', found: '{q_sales_logic}'")

    # Criteria 3: Fix Q_Shift Logic (Operator)
    # Original: dep_code.NAOK = "OPS"
    # Correct: dep_code.NAOK == "OPS"
    # Check for == "OPS" (allowing for spaces)
    c3_passed = False
    # Regex to find == followed by "OPS" or 'OPS', handling spaces
    if re.search(r'==\s*["\']OPS["\']', q_shift_logic):
        score += 30
        c3_passed = True
        feedback.append("Q_Shift logic fixed (comparison operator corrected).")
    elif "=" in q_shift_logic and "==" not in q_shift_logic:
        feedback.append("Q_Shift logic still uses assignment operator '=' instead of comparison '=='.")
    else:
        feedback.append(f"Q_Shift logic incorrect. Expected '== \"OPS\"', found: '{q_shift_logic}'")

    # Final result
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "group_logic": group_logic,
            "q_sales_logic": q_sales_logic,
            "q_shift_logic": q_shift_logic
        }
    }