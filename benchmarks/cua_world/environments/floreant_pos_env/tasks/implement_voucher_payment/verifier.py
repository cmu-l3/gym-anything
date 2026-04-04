#!/usr/bin/env python3
"""
Verifier for implement_voucher_payment task.

Checks:
1. Configuration: "Marketing Voucher" exists in DB (Coupon/Discount or Payment Type).
2. Transaction: A transaction or discount record exists with this name.
3. Item: "Cola" (or beverage) was involved.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_voucher_payment(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for execution errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"DB Query Error: {result['error']}"}

    score = 0
    feedback = []

    # Criterion 1: Configuration (40 pts)
    if result.get("config_exists", False):
        score += 40
        feedback.append("Configuration verified: 'Marketing Voucher' exists in database.")
    else:
        feedback.append("Configuration failed: 'Marketing Voucher' not found in Coupon/Discount or Payment types.")

    # Criterion 2: Usage in Transaction (40 pts)
    if result.get("transaction_exists", False):
        score += 40
        feedback.append("Transaction verified: A payment/discount named 'Marketing Voucher' was recorded.")
    else:
        feedback.append("Transaction failed: No ticket found settled with 'Marketing Voucher'.")

    # Criterion 3: Item Check (20 pts)
    # Checking if *any* Cola was ordered is a loose proxy, but sufficient combined with the others
    if result.get("item_ordered", False):
        score += 20
        feedback.append("Order content verified: 'Cola' found in recent items.")
    else:
        feedback.append("Order content warning: 'Cola' not detected in recent tickets (check spelling?).")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }