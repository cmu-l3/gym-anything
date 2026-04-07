#!/usr/bin/env python3
"""
Verifier for fiscal_position_tax_exempt task.

Scoring Breakdown (100 pts total):
1. Fiscal Position created ("Tax Exempt" or "Nonprofit"): 15 pts
2. Tax Mapping configured correctly (src -> None): 20 pts
3. Customer created ("Green Earth Foundation"): 10 pts
4. Customer assigned the Fiscal Position: 15 pts
5. Sales Order created and confirmed: 15 pts
6. Sales Order contains correct products/quantities: 10 pts
7. Sales Order has $0.00 tax: 15 pts

Pass Threshold: 65 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fiscal_position_tax_exempt(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Fiscal Position (15 pts)
    if result.get("fiscal_position_found"):
        score += 15
        feedback.append("Fiscal Position created.")
    else:
        feedback.append("Fiscal Position 'Tax Exempt' or 'Nonprofit' NOT found.")
        
    # 2. Tax Mapping (20 pts)
    if result.get("tax_mapping_correct"):
        score += 20
        feedback.append("Tax mapping configured correctly.")
    else:
        if result.get("fiscal_position_found"):
            feedback.append("Fiscal Position found but tax mapping is incorrect (not mapped to None/Empty).")
        else:
            feedback.append("Cannot verify mapping (Fiscal Position missing).")
            
    # 3. Customer (10 pts)
    if result.get("customer_found"):
        score += 10
        feedback.append("Customer 'Green Earth Foundation' created.")
    else:
        feedback.append("Customer 'Green Earth Foundation' NOT found.")
        
    # 4. Customer FP Assignment (15 pts)
    if result.get("customer_fp_correct"):
        score += 15
        feedback.append("Customer assigned correct Fiscal Position.")
    else:
        if result.get("customer_found"):
            feedback.append("Customer exists but Fiscal Position is not assigned correctly.")
    
    # 5. Sales Order Found/Confirmed (15 pts)
    if result.get("order_found"):
        score += 15
        feedback.append("Sales Order confirmed.")
    else:
        feedback.append("No confirmed Sales Order found for the customer.")
        
    # 6. Order Products (10 pts)
    if result.get("order_products_correct"):
        score += 10
        feedback.append("Order contains correct products and quantities.")
    else:
        if result.get("order_found"):
            feedback.append("Order items incorrect (wrong product or quantity).")
            
    # 7. Zero Tax (15 pts)
    if result.get("order_tax_zero"):
        score += 15
        feedback.append("Order tax is correctly $0.00.")
    else:
        if result.get("order_found"):
            val = result.get('details', {}).get('amount_tax', 'unknown')
            feedback.append(f"Order tax is NOT $0.00 (found {val}). Fiscal position may not be working.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result.get("details", {})
    }