#!/usr/bin/env python3
"""
Verifier for Credit Memo Refund task.

Evaluates if the agent correctly processed a partial refund:
1. Credit memo exists for the correct order (25 pts)
2. Correct item (Headphones) is in the refund (25 pts)
3. Correct quantity (1) is refunded (20 pts)
4. Shipping refund is 0.00 (15 pts)
5. Grand total is correct (~149.99) (15 pts)

Also checks for negative conditions (Laptop should NOT be refunded).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_credit_memo_refund(traj, env_info, task_info):
    """
    Verify the credit memo creation and details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/credit_memo_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Verification Result Data: {result}")

    # Initialize scoring
    score = 0
    feedback_parts = []
    passed = False
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_sku = metadata.get('target_sku', 'HEADPHONES-001')
    target_qty = metadata.get('target_qty', 1)
    forbidden_sku = metadata.get('forbidden_sku', 'LAPTOP-001')
    expected_shipping = metadata.get('expected_shipping_refund', 0.0)
    expected_total = metadata.get('expected_grand_total', 149.99)
    tolerance = metadata.get('tolerance', 0.05)

    # 1. Check if credit memo exists (25 pts)
    if not result.get('credit_memo_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No credit memo found for John Smith's order created during the task."
        }
    
    score += 25
    feedback_parts.append("Credit memo created")
    
    cm = result.get('credit_memo', {})
    items = cm.get('items', [])
    
    # 2. Check Items (Target vs Forbidden) (25 pts)
    headphones_item = next((item for item in items if item['sku'] == target_sku), None)
    laptop_item = next((item for item in items if item['sku'] == forbidden_sku), None)
    
    if headphones_item:
        score += 25
        feedback_parts.append(f"Correct item ({target_sku}) included")
    else:
        feedback_parts.append(f"Missing target item: {target_sku}")

    if laptop_item and float(laptop_item.get('qty', 0)) > 0:
        score -= 25 # Penalty for refunding the wrong item
        feedback_parts.append(f"PENALTY: Refunding incorrect item ({forbidden_sku})")
        
    # 3. Check Quantity (20 pts)
    qty_correct = False
    if headphones_item:
        qty = float(headphones_item.get('qty', 0))
        if abs(qty - target_qty) < 0.01:
            score += 20
            qty_correct = True
            feedback_parts.append(f"Quantity correct ({qty})")
        else:
            feedback_parts.append(f"Quantity incorrect: expected {target_qty}, got {qty}")
            
    # 4. Check Shipping Refund (15 pts)
    shipping_amt = float(cm.get('shipping_amount', 0))
    if abs(shipping_amt - expected_shipping) < 0.01:
        score += 15
        feedback_parts.append("Shipping refund correct ($0.00)")
    else:
        feedback_parts.append(f"Shipping refund incorrect: expected ${expected_shipping}, got ${shipping_amt}")
        
    # 5. Check Grand Total (15 pts)
    grand_total = float(cm.get('grand_total', 0))
    if abs(grand_total - expected_total) <= (expected_total * tolerance):
        score += 15
        feedback_parts.append(f"Grand total correct (${grand_total})")
    else:
        feedback_parts.append(f"Grand total incorrect: expected ~${expected_total}, got ${grand_total}")

    # Cap score at 0 if negative
    score = max(0, score)
    
    # Pass threshold
    if score >= 60:
        passed = True
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }