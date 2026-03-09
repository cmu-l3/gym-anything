#!/usr/bin/env python3
"""
Verifier for allocate_freight_cost task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_allocate_freight_cost(traj, env_info, task_info):
    """
    Verify that the freight invoice was created correctly.
    Key requirement: Line item for 'Chang' has value $45.00 but Qty is 0/Empty.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # 1. Invoice Created and Found (20 pts)
    if result.get("invoice_found"):
        score += 20
        feedback_parts.append("Invoice found")
    else:
        return {"passed": False, "score": 0, "feedback": "No matching purchase invoice found"}

    # 2. Correct Supplier (20 pts)
    if result.get("supplier") == "Exotic Liquids":
        score += 20
        feedback_parts.append("Correct supplier")
    else:
        feedback_parts.append(f"Wrong supplier: {result.get('supplier')}")

    # 3. Correct Total Amount (20 pts)
    if abs(result.get("total_amount", 0) - 45.0) < 0.01:
        score += 20
        feedback_parts.append("Correct total amount ($45.00)")
    else:
        feedback_parts.append(f"Wrong amount: {result.get('total_amount')}")

    # 4. Landed Cost Logic (Qty = 0) (40 pts)
    # This is the core accounting logic test
    line_items = result.get("line_items", [])
    chang_item = next((item for item in line_items if "Chang" in item.get("item", "")), None)
    
    if chang_item:
        qty = chang_item.get("qty", 1)
        # We expect qty to be 0 (meaning blank or explicitly 0 in Manager view)
        if qty == 0:
            score += 40
            feedback_parts.append("Correctly allocated cost (Qty=0)")
        else:
            feedback_parts.append("FAIL: Quantity was set to 1. This increases stock instead of revaluing it.")
    else:
        feedback_parts.append("Item 'Chang' not found on invoice")

    # Anti-gaming: Check if app was running
    if str(result.get("app_was_running")).lower() == "true":
        pass # Good
    else:
        feedback_parts.append("Warning: Browser not running at end of task")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }