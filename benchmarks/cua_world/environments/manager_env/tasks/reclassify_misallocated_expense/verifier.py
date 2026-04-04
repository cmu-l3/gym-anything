#!/usr/bin/env python3
"""
Verifier for reclassify_misallocated_expense task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reclassify_misallocated_expense(traj, env_info, task_info):
    """
    Verifies if the agent created the 'Meals & Entertainment' account 
    and reclassified the City Grill payment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # Criterion 1: New Account Created (30 pts)
    if result.get("meals_account_exists"):
        score += 30
        feedback.append("Success: 'Meals & Entertainment' account created.")
    else:
        feedback.append("Fail: 'Meals & Entertainment' account NOT found.")
        
    # Criterion 2: Payment Found (20 pts)
    if result.get("target_payment_found"):
        score += 20
        feedback.append("Success: City Grill payment found.")
    else:
        feedback.append("Fail: City Grill payment deleted or not found.")
        
    # Criterion 3: Payment Reclassified (50 pts)
    account = result.get("target_payment_account")
    if account == "Meals & Entertainment":
        score += 50
        feedback.append("Success: Payment correctly reclassified to 'Meals & Entertainment'.")
    elif account == "Office Supplies":
        feedback.append("Fail: Payment is still under 'Office Supplies'.")
    else:
        feedback.append(f"Fail: Payment account is '{account}', expected 'Meals & Entertainment'.")
        
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }