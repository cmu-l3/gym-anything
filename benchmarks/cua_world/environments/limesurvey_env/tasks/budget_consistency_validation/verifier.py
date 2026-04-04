#!/usr/bin/env python3
"""
Verifier for budget_consistency_validation task.

Checks if the user implemented a cross-question validation rule in LimeSurvey.
Logic: Sum of expenses (Q_EXPENSES) must be <= Income (Q_INCOME).
"""

import json
import tempfile
import os
import re

def verify_budget_consistency_validation(traj, env_info, task_info):
    """
    Verify validation equation and tip.
    
    Criteria:
    1. Equation exists and is not empty.
    2. Equation references Q_INCOME.
    3. Equation uses summation (sum() or +).
    4. Equation uses comparison (<=, <, le, lt).
    5. Tip exists and references {Q_INCOME}.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    eq = result.get("validation_equation", "").strip()
    tip = result.get("validation_tip", "").strip()
    
    score = 0
    feedback_parts = []
    
    # Check 1: Logic defined (40 pts)
    if eq:
        score += 40
        feedback_parts.append("Validation equation is set")
    else:
        feedback_parts.append("Validation equation is empty")
        return {"passed": False, "score": 0, "feedback": "Validation equation not set"}

    # Check 2: References Q_INCOME (20 pts)
    # Check for Q_INCOME or Q_INCOME.NAOK
    if re.search(r"Q_INCOME", eq, re.IGNORECASE):
        score += 20
        feedback_parts.append("References Q_INCOME")
    else:
        feedback_parts.append("Equation does not reference Q_INCOME")

    # Check 3: Logic uses summation (20 pts)
    # Looking for sum(...) OR arithmetic + 
    # Valid patterns: sum(self), sum(Q_EXPENSES), Q_EXPENSES_SQ001 + Q_EXPENSES_SQ002...
    if "sum" in eq.lower() or "+" in eq:
        score += 20
        feedback_parts.append("Uses summation")
    else:
        feedback_parts.append("Equation does not appear to sum the expenses")
    
    # Implicit check for operator (part of logic check really, but let's be lenient if they did sum and income)
    # We want to see <= or < or le or lt
    valid_operators = ["<=", "<", "le", "lt"]
    has_operator = any(op in eq.lower() for op in valid_operators)
    if not has_operator:
        feedback_parts.append("Warning: Logic comparison operator (<, <=) not found")

    # Check 4: Validation Tip (20 pts)
    # Must contain text "cannot exceed" and variable "{Q_INCOME}"
    tip_score = 0
    if "cannot exceed" in tip.lower():
        tip_score += 10
    if "{Q_INCOME}" in tip:
        tip_score += 10
    
    score += tip_score
    if tip_score == 20:
        feedback_parts.append("Validation tip correct")
    elif tip_score > 0:
        feedback_parts.append("Validation tip partially correct")
    else:
        feedback_parts.append("Validation tip missing or incorrect")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"equation": eq, "tip": tip}
    }