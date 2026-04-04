#!/usr/bin/env python3
"""
Verifier for bill_reimbursable_expense task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bill_reimbursable_expense(traj, env_info, task_info):
    """
    Verify that the agent enabled the module, created the payment, and invoiced it.
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: Module Enabled (10 pts)
    if result.get("module_enabled"):
        score += 10
        feedback_parts.append("Billable Expenses module enabled")
    else:
        feedback_parts.append("Billable Expenses module NOT enabled")

    # Criterion 2: Payment Created (25 pts)
    if result.get("payment_found"):
        score += 25
        feedback_parts.append("Payment of 120.00 found")
    else:
        feedback_parts.append("Payment of 120.00 NOT found")

    # Criterion 3: Payment Attributes Correct (15 pts)
    # Checks link to Ernst Handel and Billable Expenses account
    if result.get("payment_correct"):
        score += 15
        feedback_parts.append("Payment correctly linked to Customer/Billable Expenses")
    elif result.get("payment_found"):
        feedback_parts.append("Payment found but attributes incorrect (wrong customer/account?)")

    # Criterion 4: Invoice Created (25 pts)
    if result.get("invoice_found"):
        score += 25
        feedback_parts.append("Sales Invoice found for Ernst Handel")
    else:
        feedback_parts.append("Sales Invoice NOT found")

    # Criterion 5: Expense Linked (25 pts)
    # Checks if the invoice actually includes the billable expense item
    if result.get("invoice_linked"):
        score += 25
        feedback_parts.append("Invoice correctly includes the Billable Expense item")
    elif result.get("invoice_found"):
        feedback_parts.append("Invoice found but Billable Expense item not properly linked/included")

    # Final check
    # We require the expense to be linked for a pass to ensure the workflow was followed.
    passed = (score >= 75) and result.get("invoice_linked")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }