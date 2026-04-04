#!/usr/bin/env python3
"""
Verifier for process_sales_quote task.

Criteria:
1. Sales Order count increased (indicates new creation).
2. Sales Order for 'Ernst Handel' exists.
3. Contains 'Steeleye Stout' with Quantity = 24.
4. Contains note 'Customer confirmed via email'.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_sales_quote(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    order_found = result.get('order_found', False)
    order_data = result.get('order_data', {})
    
    # Check 1: Order Created (20 pts)
    # We verify count increased OR we found a matching new order
    if final_count > initial_count:
        score += 20
        feedback.append("New Sales Order created (count increased).")
    else:
        feedback.append("Sales Order count did not increase.")

    # Check 2: Order Details (80 pts)
    if order_found:
        # 2a. Correct Customer (Verified in export script)
        score += 10 
        feedback.append("Sales Order for Ernst Handel found.")
        
        # 2b. Quantity Adjusted (35 pts)
        qty = order_data.get('qty_stout', 0)
        if qty == 24:
            score += 35
            feedback.append("Quantity correctly updated to 24.")
        elif qty == 20:
            feedback.append("Quantity was NOT updated (remained 20).")
        else:
            feedback.append(f"Quantity mismatch: found {qty}, expected 24.")
            
        # 2c. Note Added (35 pts)
        if order_data.get('has_note', False):
            score += 35
            feedback.append("Note 'confirmed via email' found.")
        else:
            feedback.append("Required note missing.")
    else:
        feedback.append("No valid Sales Order found for Ernst Handel.")

    passed = score >= 80  # Requires creation + quantity update + note (mostly)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }