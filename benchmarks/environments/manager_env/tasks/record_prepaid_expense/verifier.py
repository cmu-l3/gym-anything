#!/usr/bin/env python3
"""
Verifier for record_prepaid_expense task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_prepaid_expense(traj, env_info, task_info):
    """
    Verifies that the Prepaid Insurance account was created correctly and the payment recorded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # Scoring
    score = 0
    feedback = []

    # Criterion 1: Account Created (30 pts)
    if result.get("account_exists"):
        score += 30
        feedback.append("Acccount 'Prepaid Insurance' created.")
    else:
        feedback.append("Account 'Prepaid Insurance' NOT found.")

    # Criterion 2: Account Type (20 pts)
    # Must be an Asset (appear in Assets section of Summary)
    if result.get("is_asset"):
        score += 20
        feedback.append("Account is correctly classified as an Asset.")
    elif result.get("account_exists"):
        feedback.append("Account exists but does not appear to be an Asset (check classification).")

    # Criterion 3: Payment Recorded (20 pts)
    if result.get("payment_found"):
        score += 20
        feedback.append("Payment found.")
    else:
        feedback.append("Payment of 2,400.00 NOT found.")

    # Criterion 4: Payee Correct (10 pts)
    if result.get("payee_correct"):
        score += 10
        feedback.append("Payee 'Fairfax Insurance' is correct.")
    else:
        feedback.append("Payee incorrect or missing.")
        
    # Criterion 5: Allocation Correct (20 pts)
    # Checked by verifying the account balance reflects the payment
    if result.get("allocation_correct"):
        score += 20
        feedback.append("Payment correctly allocated to Prepaid Insurance.")
    elif result.get("payment_found") and result.get("account_exists"):
        feedback.append("Payment exists but does not seem allocated to Prepaid Insurance (balance mismatch).")

    # Pass Threshold: 70 points
    # Requires at least Account + Type + Payment OR Account + Payment + Allocation
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }