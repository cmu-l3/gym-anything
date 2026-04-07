#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analytic_cost_allocation(traj, env_info, task_info):
    """
    Verify the Odoo Analytic Cost Allocation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_allocations = metadata.get('allocations', {})

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

    # 1. Analytic Plan (10 pts)
    if result.get("plan_found"):
        score += 10
        feedback.append("Analytic Plan 'Department Costs' created.")
    else:
        feedback.append("Analytic Plan 'Department Costs' NOT found.")

    # 2. Analytic Accounts (24 pts - 8 each)
    found_accounts = result.get("accounts_found_names", [])
    required_accounts = ["Engineering Dept", "Marketing Dept", "Operations Dept"]
    for acc in required_accounts:
        if acc in found_accounts:
            score += 8
            feedback.append(f"Account '{acc}' found.")
        else:
            feedback.append(f"Account '{acc}' NOT found.")

    # 3. Vendor Bill Existence & Posting (25 pts)
    if result.get("bill_found"):
        score += 10
        feedback.append("Posted Vendor bill found.")
        if result.get("bill_correct_amount"):
            score += 15
            feedback.append("Bill amount ($12,000) is correct.")
        else:
            amt = result.get("bill_amount", 0)
            feedback.append(f"Bill amount (${amt}) is incorrect.")
    else:
        feedback.append("No posted vendor bill for 'Deco Addict' found.")

    # 4. Allocations (41 pts)
    # Engineering: 50% (12 pts)
    # Marketing: 30% (10 pts)
    # Operations: 20% (9 pts)
    # Bonus 10 pts implicit in total if all correct? Let's map strict points.
    # Total remaining: 100 - 10 - 24 - 25 = 41 points.
    
    actual_allocations = result.get("allocations", {})
    
    # Check Engineering (target 50)
    eng_val = actual_allocations.get("Engineering Dept", 0)
    if 45 <= eng_val <= 55:
        score += 14
        feedback.append(f"Engineering allocation ({eng_val}%) correct.")
    elif eng_val > 0:
        score += 5
        feedback.append(f"Engineering allocation ({eng_val}%) incorrect (target 50%).")
    else:
        feedback.append("Engineering allocation missing.")

    # Check Marketing (target 30)
    mkt_val = actual_allocations.get("Marketing Dept", 0)
    if 25 <= mkt_val <= 35:
        score += 14
        feedback.append(f"Marketing allocation ({mkt_val}%) correct.")
    elif mkt_val > 0:
        score += 5
        feedback.append(f"Marketing allocation ({mkt_val}%) incorrect (target 30%).")
    else:
        feedback.append("Marketing allocation missing.")

    # Check Operations (target 20)
    ops_val = actual_allocations.get("Operations Dept", 0)
    if 15 <= ops_val <= 25:
        score += 13
        feedback.append(f"Operations allocation ({ops_val}%) correct.")
    elif ops_val > 0:
        score += 5
        feedback.append(f"Operations allocation ({ops_val}%) incorrect (target 20%).")
    else:
        feedback.append("Operations allocation missing.")

    # Check for extra/wrong allocations? (Optional, skipping for simplicity)

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }