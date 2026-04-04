#!/usr/bin/env python3
"""
Verifier for record_customer_refund task.
Verifies that a payment was created with specific details in Manager.io.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_customer_refund(traj, env_info, task_info):
    """
    Verify the customer refund payment.
    
    Criteria:
    1. Payment count increased (implies creation) - 20 pts
    2. Payment for 'Alfreds Futterkiste' found - 30 pts
    3. Amount is 50.00 - 30 pts
    4. Account is 'Accounts receivable' - 10 pts
    5. Source is 'Cash on Hand' - 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
            
    # Evaluation
    score = 0
    feedback_parts = []
    
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    payment_found = result.get("payment_found", False)
    details = result.get("payment_details", {})
    
    # Criterion 1: Creation (Count Check)
    if final_count > initial_count:
        score += 20
        feedback_parts.append("New payment record created.")
    else:
        feedback_parts.append("No new payment record detected.")
        
    # Criteria 2-5: Data Verification
    if payment_found:
        # Payee
        if details.get("payee_correct"):
            score += 30
            feedback_parts.append("Correct Payee (Alfreds Futterkiste).")
        else:
            feedback_parts.append("Incorrect Payee.")
            
        # Amount
        if details.get("amount_correct"):
            score += 30
            feedback_parts.append("Correct Amount (50.00).")
        else:
            feedback_parts.append("Incorrect Amount.")
            
        # Account (Ledger)
        if details.get("account_correct"):
            score += 10
            feedback_parts.append("Correct Account (Accounts receivable).")
        else:
            feedback_parts.append("Incorrect Account (should be Accounts receivable).")
            
        # Source (Bank/Cash)
        if details.get("source_correct"):
            score += 10
            feedback_parts.append("Correct Source (Cash on Hand).")
        else:
            feedback_parts.append("Incorrect Source (should be Cash on Hand).")
            
    else:
        feedback_parts.append("Target payment details NOT found.")

    passed = score >= 80  # Requires Creation + Payee + Amount at minimum
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }