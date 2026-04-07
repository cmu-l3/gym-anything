#!/usr/bin/env python3
"""
Verifier for approve_expense_report task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_approve_expense_report(traj, env_info, task_info):
    """
    Verifies that the expense report for Eli Lambert was approved.
    
    Criteria:
    1. Report exists and was found in DB (15 pts)
    2. Report is in 'approve' or 'post' or 'done' state (50 pts)
       (Note: Odoo 17 state keys: 'draft', 'submit', 'approve', 'post', 'done')
    3. Correct employee (15 pts)
    4. Anti-gaming: It is the SAME record ID created during setup (10 pts)
    5. Amount is correct (~925.00) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # 1. Report Exists (15 pts)
    if result.get('found'):
        score += 15
        feedback_parts.append("Expense report found")
    else:
        return {"passed": False, "score": 0, "feedback": "Expense report not found in database"}

    # 2. State Check (50 pts)
    # Expected: 'approve' (Approved). 'post' (Posted) or 'done' (Paid) are also acceptable as they imply approval.
    current_state = result.get('current_state', '')
    acceptable_states = ['approve', 'post', 'done']
    
    if current_state in acceptable_states:
        score += 50
        feedback_parts.append(f"State is '{current_state}' (Approved)")
    else:
        feedback_parts.append(f"State is '{current_state}' (Expected: Approved)")

    # 3. Employee Check (15 pts)
    if result.get('employee_match'):
        score += 15
        feedback_parts.append("Correct employee")
    else:
        feedback_parts.append("Wrong employee assigned")

    # 4. Anti-Gaming: ID Match (10 pts)
    # Ensures the agent didn't delete the submitted one and create a new pre-approved one
    if result.get('initial_id_match'):
        score += 10
        feedback_parts.append("Valid record transition (ID matches)")
    else:
        feedback_parts.append("Warning: Report ID changed (possible re-creation)")

    # 5. Amount Check (10 pts)
    total = result.get('total_amount', 0.0)
    expected = 925.0
    if abs(total - expected) < 1.0:
        score += 10
        feedback_parts.append(f"Total amount correct (${total})")
    else:
        feedback_parts.append(f"Total amount mismatch (${total}, expected ${expected})")

    passed = score >= 80  # Requires finding it, approving it, and most other checks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }