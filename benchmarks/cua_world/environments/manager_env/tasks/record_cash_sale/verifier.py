#!/usr/bin/env python3
"""
Verifier for record_cash_sale task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_cash_sale(traj, env_info, task_info):
    """
    Verifies that a Cash Receipt was created for 'Walk-in Customer' 
    with 'Chai' and Qty 12, directly allocated (not AR).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Criteria
    score = 0
    feedback = []
    
    # Check if receipt found
    if not result.get("receipt_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No receipt found for 'Walk-in Customer'. Error: {result.get('error')}"
        }
    
    details = result.get("details", {})
    
    # Criterion 1: Receipt Exists (20 pts)
    score += 20
    feedback.append("Receipt found.")
    
    # Criterion 2: Payer Name (15 pts)
    payer = details.get("payer", "")
    if "Walk-in" in payer:
        score += 15
        feedback.append(f"Payer correct: {payer}")
    else:
        feedback.append(f"Payer incorrect: {payer}")
        
    # Criterion 3: Bank Account (15 pts)
    account = details.get("account", "")
    if "Cash on Hand" in account:
        score += 15
        feedback.append(f"Bank account correct: {account}")
    else:
        feedback.append(f"Bank account incorrect: {account}")
        
    # Criterion 4: Item & Qty (30 pts)
    if details.get("has_chai") and details.get("has_qty_12"):
        score += 30
        feedback.append("Line item 'Chai' with Qty 12 found.")
    else:
        feedback.append("Line item details missing or incorrect (Expected Chai, Qty 12).")
        
    # Criterion 5: Direct Sale (No AR) (20 pts)
    # If "Accounts receivable" is present, they likely did an invoice payment workflow
    if not details.get("is_ar_linked"):
        score += 20
        feedback.append("Direct sale (no Accounts Receivable link detected).")
    else:
        feedback.append("Warning: Receipt appears linked to Accounts Receivable (Invoice workflow used instead of direct sale).")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details
    }