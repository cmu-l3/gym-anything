#!/usr/bin/env python3
"""
Verifier for Setup Volume Discount task.

Scoring Criteria (Total 100):
1. Promotion exists with correct name (15 pts)
2. Offer type is 'order_item_percentage_off' (20 pts)
   - CRITICAL: Must be item-level, not order-level
3. Percentage is 10% (0.10) (15 pts)
4. Quantity condition exists (20 pts)
5. Quantity threshold is 5 (10 pts)
6. No coupon required (10 pts)
7. Assigned to correct store (10 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_volume_discount(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_offer_plugin = metadata.get('expected_offer_plugin', 'order_item_percentage_off')
    expected_percentage = metadata.get('expected_percentage', 0.10)
    expected_condition_plugin = metadata.get('expected_condition_plugin', 'order_item_quantity')
    expected_quantity = metadata.get('expected_quantity', 5)

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # Gate Check: Promotion Found
    if not result.get('promotion_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No promotion with 'Volume Discount' in the name was found."
        }

    # Criterion 1: Promotion Exists (15 pts)
    score += 15
    feedback_parts.append("Promotion created")

    # Criterion 2: Offer Type (20 pts)
    actual_offer = result.get('offer_plugin', '')
    if actual_offer == expected_offer_plugin:
        score += 20
        feedback_parts.append("Correct item-level offer type")
    elif actual_offer == 'order_percentage_off':
        feedback_parts.append("Wrong offer type: 'Order percentage off' used instead of 'Order item percentage off'")
    else:
        feedback_parts.append(f"Wrong offer type: {actual_offer}")

    # Criterion 3: Percentage Value (15 pts)
    parsed_vals = result.get('parsed_values', {})
    raw_pct = parsed_vals.get('percentage')
    try:
        pct_val = float(raw_pct) if raw_pct else 0.0
        # Allow small float variance or exact 0.10
        if abs(pct_val - expected_percentage) < 0.01:
            score += 15
            feedback_parts.append(f"Correct percentage ({pct_val})")
        else:
            feedback_parts.append(f"Incorrect percentage: {pct_val} (expected {expected_percentage})")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid percentage value: {raw_pct}")

    # Criterion 4: Quantity Condition Exists (20 pts)
    if result.get('has_quantity_condition'):
        score += 20
        feedback_parts.append("Quantity condition present")
    else:
        feedback_parts.append("Missing 'Order item quantity' condition")

    # Criterion 5: Quantity Threshold (10 pts)
    raw_qty = parsed_vals.get('quantity')
    try:
        qty_val = int(raw_qty) if raw_qty else 0
        if qty_val == expected_quantity:
            score += 10
            feedback_parts.append(f"Correct quantity threshold ({qty_val})")
        elif result.get('has_quantity_condition'):
            feedback_parts.append(f"Incorrect quantity: {qty_val} (expected {expected_quantity})")
    except (ValueError, TypeError):
        if result.get('has_quantity_condition'):
            feedback_parts.append(f"Invalid quantity value: {raw_qty}")

    # Criterion 6: No Coupon Required (10 pts)
    require_coupon = result.get('require_coupon')
    # require_coupon is usually 1 (true) or 0 (false) in DB
    if require_coupon == 0 or require_coupon == '0':
        score += 10
        feedback_parts.append("Auto-applied (no coupon)")
    else:
        feedback_parts.append("Incorrectly requires a coupon")

    # Criterion 7: Store Assigned (10 pts)
    if result.get('store_assigned'):
        score += 10
        feedback_parts.append("Store assigned correctly")
    else:
        feedback_parts.append("Not assigned to Urban Electronics store")

    # Check for active status (bonus check, already implicit in existence usually)
    status = result.get('promotion_status')
    if str(status) != '1':
        feedback_parts.append("Warning: Promotion is disabled")
        # Deduct 5 points if score > 5 to penalize disabled promotion
        if score >= 5:
            score -= 5

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }