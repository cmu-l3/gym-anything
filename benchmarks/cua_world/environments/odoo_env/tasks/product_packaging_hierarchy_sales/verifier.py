#!/usr/bin/env python3
"""
Verifier for product_packaging_hierarchy_sales task.

Scoring (100 points total):
- Feature "Product Packagings" enabled: 20 points
- "Retail Pack" (12 units) defined correctly: 20 points
- "Master Case" (48 units) defined correctly: 20 points
- Sales Order created for correct customer: 10 points
- Sales Order confirmed: 10 points
- Sales Order total quantity is exactly 211: 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_packaging_hierarchy_sales(traj, env_info, task_info):
    """
    Verify the configuration of product packagings and the resulting sales order.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/task_result.json', temp_file.name)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        try:
            with open(temp_file.name) as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result file is not valid JSON: {e}"}
    finally:
        os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    score = 0
    feedback_parts = []
    
    # Criterion 1: Feature Enabled (20 pts)
    # If the user successfully created packagings, the feature IS enabled implicitly
    # regardless of the group check (which might be flaky depending on user context).
    # So we give points if feature_enabled is True OR if packagings were found.
    feature_enabled = result.get('feature_enabled', False)
    retail_found = result.get('retail_pack_found', False)
    master_found = result.get('master_case_found', False)
    
    if feature_enabled or retail_found or master_found:
        score += 20
        feedback_parts.append("Product Packagings feature enabled (20/20)")
    else:
        feedback_parts.append("Product Packagings feature NOT enabled (0/20)")

    # Criterion 2: Retail Pack (20 pts)
    if retail_found:
        score += 20
        feedback_parts.append("Retail Pack (12 units) configured correctly (20/20)")
    else:
        feedback_parts.append("Retail Pack (12 units) NOT found (0/20)")

    # Criterion 3: Master Case (20 pts)
    if master_found:
        score += 20
        feedback_parts.append("Master Case (48 units) configured correctly (20/20)")
    else:
        feedback_parts.append("Master Case (48 units) NOT found (0/20)")

    # Criterion 4: Sales Order Exists (10 pts)
    if result.get('sales_order_found'):
        score += 10
        feedback_parts.append(f"Sales Order found for GreenLife Retailers (10/10)")
    else:
        feedback_parts.append("Sales Order for GreenLife Retailers NOT found (0/10)")

    # Criterion 5: Sales Order Confirmed (10 pts)
    if result.get('sales_order_confirmed'):
        score += 10
        feedback_parts.append("Sales Order confirmed (10/10)")
    else:
        feedback_parts.append("Sales Order not confirmed (0/10)")

    # Criterion 6: Total Quantity (20 pts)
    # Target: 3 * 48 + 5 * 12 + 7 = 144 + 60 + 7 = 211
    target_qty = 211.0
    actual_qty = result.get('sales_order_total_qty', 0.0)
    
    if abs(actual_qty - target_qty) < 0.1:
        score += 20
        feedback_parts.append(f"Order quantity correct: {int(actual_qty)} units (20/20)")
    else:
        feedback_parts.append(f"Order quantity incorrect: expected {int(target_qty)}, got {int(actual_qty)} (0/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }