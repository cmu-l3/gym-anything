#!/usr/bin/env python3
"""
Verifier for submit_expense_on_behalf task.
Verifies Odoo expense record creation via exported JSON data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_submit_expense_on_behalf(traj, env_info, task_info):
    """
    Verifies that the agent created an expense for 'Marc Demo'.
    
    Scoring Criteria:
    1. Expense record found (20 pts)
    2. Correct Employee (Marc Demo) (40 pts) - CRITICAL
    3. Correct Amount (145.50) (20 pts)
    4. Correct Product (Meals) (10 pts)
    5. Created during task (10 pts) - Anti-gaming
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if record exists
    if not result.get("expense_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No expense record found with description 'Client Dinner with Acme Corp'."
        }
    
    score += 20
    feedback_parts.append("Expense record found (+20)")

    # 2. Check Employee (Critical)
    employee = result.get("employee_name", "")
    if "Marc Demo" in employee:
        score += 40
        feedback_parts.append("Correct employee: Marc Demo (+40)")
    elif "Mitchell Admin" in employee:
        feedback_parts.append("FAIL: Employee is still 'Mitchell Admin' (Default not changed)")
    else:
        feedback_parts.append(f"FAIL: Employee is '{employee}'")

    # 3. Check Amount
    amount = result.get("amount", 0.0)
    if abs(amount - 145.50) < 0.1:
        score += 20
        feedback_parts.append("Correct amount: 145.50 (+20)")
    else:
        feedback_parts.append(f"Incorrect amount: {amount} (expected 145.50)")

    # 4. Check Product
    product = result.get("product_name", "")
    if "Meals" in product:
        score += 10
        feedback_parts.append("Correct product: Meals (+10)")
    else:
        feedback_parts.append(f"Incorrect product: {product}")

    # 5. Check Timestamp (Anti-gaming)
    if result.get("created_during_task"):
        score += 10
        feedback_parts.append("Created during task (+10)")
    else:
        feedback_parts.append("Warning: Record timestamp predates task start (Pre-existing data?)")

    # Pass threshold: 80 points.
    # Basically requires Employee name to be correct + record found + amount.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }