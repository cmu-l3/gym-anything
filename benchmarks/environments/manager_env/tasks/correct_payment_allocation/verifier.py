#!/usr/bin/env python3
"""
Verifier for correct_payment_allocation task.
Checks if the specific payment was split correctly between two accounts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_payment_allocation(traj, env_info, task_info):
    """
    Verifies that the agent correctly split the payment.
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

    # Basic Checks
    if not result.get("payment_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The target payment record could not be found. Did you delete it instead of editing?"
        }

    data = result.get("data", {})
    meta = result.get("metadata_ref", {})
    accounts_map = meta.get("accounts", {})
    
    score = 0
    feedback = []
    
    # 1. Check if it's the same record (UUID match is implicit since we fetched by UUID)
    # 2. Check Total Amount (should still be 600)
    lines = data.get("Lines", [])
    total_amount = sum(float(line.get("Amount", 0)) for line in lines)
    
    if abs(total_amount - 600.00) < 0.01:
        score += 20
        feedback.append("Total amount correct (600.00).")
    else:
        feedback.append(f"Total amount incorrect: {total_amount} (expected 600.00).")

    # 3. Check Split (Line Count)
    if len(lines) == 2:
        score += 30
        feedback.append("Transaction has correct number of lines (2).")
    elif len(lines) > 2:
        score += 10
        feedback.append(f"Transaction has {len(lines)} lines (expected 2).")
    else:
        feedback.append("Transaction was not split (only 1 line).")

    # 4. Check Allocations
    # We expect:
    # - Office Supplies (uuid from meta): 200.00
    # - Repairs (uuid from meta): 400.00
    
    office_uuid = accounts_map.get("office_supplies")
    repairs_uuid = accounts_map.get("repairs")
    
    found_office = False
    found_repairs = False
    
    for line in lines:
        acct = line.get("Account")
        amt = float(line.get("Amount", 0))
        
        if acct == office_uuid:
            if abs(amt - 200.00) < 0.01:
                score += 25
                found_office = True
                feedback.append("Office Supplies allocation correct (200.00).")
            else:
                feedback.append(f"Office Supplies allocation wrong: {amt}.")
        
        elif acct == repairs_uuid:
            if abs(amt - 400.00) < 0.01:
                score += 25
                found_repairs = True
                feedback.append("Repairs allocation correct (400.00).")
            else:
                feedback.append(f"Repairs allocation wrong: {amt}.")
                
    if not found_office:
        feedback.append("Office Supplies line item not found.")
    if not found_repairs:
        feedback.append("Repairs and Maintenance line item not found.")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }