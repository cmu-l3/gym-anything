#!/usr/bin/env python3
"""
Verifier for vendor_return_refund_workflow task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_return_refund(traj, env_info, task_info):
    """
    Verifies:
    1. Return picking exists for 3 units (Stock -> Vendor).
    2. Vendor Credit Note exists and is posted for correct amount.
    3. Stock level reflects the return (10 - 3 = 7).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Data extraction
    return_found = result.get('return_found', False)
    return_qty = result.get('return_qty', 0)
    refund_found = result.get('refund_found', False)
    refund_amount = result.get('refund_amount', 0.0)
    current_stock = result.get('current_stock', 0)
    unit_price = result.get('unit_price', 0.0)
    
    expected_return_qty = 3
    expected_refund = expected_return_qty * unit_price
    expected_stock = 7 # 10 - 3

    # Criterion 1: Return Transfer (40 pts)
    if return_found:
        if return_qty == expected_return_qty:
            score += 40
            feedback_parts.append(f"Return transfer correct ({return_qty} units).")
        else:
            score += 20
            feedback_parts.append(f"Return transfer found but wrong quantity ({return_qty} vs {expected_return_qty}).")
    else:
        feedback_parts.append("No return transfer found.")

    # Criterion 2: Credit Note (40 pts)
    if refund_found:
        # Check amount with small tolerance
        if abs(refund_amount - expected_refund) < 1.0:
            score += 40
            feedback_parts.append(f"Credit note correct (${refund_amount}).")
        else:
            score += 20
            feedback_parts.append(f"Credit note found but wrong amount (${refund_amount} vs ${expected_refund}).")
    else:
        feedback_parts.append("No posted credit note found.")

    # Criterion 3: Stock Level (20 pts)
    if current_stock == expected_stock:
        score += 20
        feedback_parts.append(f"Stock level correct ({current_stock}).")
    else:
        feedback_parts.append(f"Stock level incorrect ({current_stock} vs {expected_stock}).")

    passed = (score >= 70) and return_found and refund_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }