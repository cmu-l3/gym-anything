#!/usr/bin/env python3
"""
Verifier for employee_expense_report task.

Criteria:
1. Expense Report exists for Sarah Chen (10 pts)
2. Report contains 5 expenses with correct amounts (10 pts each = 50 pts)
3. Report is in 'approve' or 'post' or 'done' state (20 pts)
4. Journal Entry is posted (20 pts)
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_employee_expense_report(traj, env_info, task_info):
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

    if not result.get('report_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No expense report found for Sarah Chen."
        }

    report = result['report']
    expenses = result['expenses']
    score = 0
    feedback = []

    # 1. Report Exists (10 pts)
    score += 10
    feedback.append("Expense report created.")

    # 2. Check Expenses (50 pts total)
    # Expected items from metadata
    expected_items = task_info['metadata']['items']
    tolerance = task_info['metadata']['tolerance_pct']

    matched_count = 0
    
    # We verify by finding a matching amount for each expected item
    # This is a simple matching; strictly we should check names too, but names vary. 
    # Amounts are unique enough in this set.
    
    # Clone expenses to avoid double counting
    available_expenses = list(expenses)
    
    for item in expected_items:
        target = item['amount']
        found = False
        for i, exp in enumerate(available_expenses):
            try:
                val = float(exp['amount'])
                if math.isclose(val, target, rel_tol=tolerance):
                    available_expenses.pop(i)
                    found = True
                    break
            except:
                continue
        
        if found:
            matched_count += 1
            score += 10 # 10 pts per item
            feedback.append(f"Found expense item for ${target}.")
        else:
            feedback.append(f"Missing or incorrect expense item for ${target}.")

    # 3. Report State (20 pts)
    state = report.get('state')
    # Valid states indicating progress: approve, post, done
    if state in ['approve', 'post', 'done']:
        score += 20
        feedback.append(f"Report state '{state}' is valid (approved).")
    elif state == 'submit':
        score += 10
        feedback.append("Report submitted but not approved.")
    else:
        feedback.append(f"Report in state '{state}' (expected approved/posted).")

    # 4. Journal Entry Posted (20 pts)
    # 'done' state usually implies posted in Odoo 17 Expenses
    move_state = report.get('move_state')
    if state == 'done' or move_state == 'posted':
        score += 20
        feedback.append("Journal entries posted successfully.")
    else:
        feedback.append("Journal entries not posted.")

    # Threshold
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }