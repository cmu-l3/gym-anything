#!/usr/bin/env python3
"""Verifier for MAP Pricing Config task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_pricing_config(traj, env_info, task_info):
    """
    Verify MAP configuration.
    
    Criteria:
    1. Global MAP Enabled (sales/msrp/enabled = 1) - 20 pts
    2. Global Message Correct ("Add to cart to see our special low price!") - 15 pts
    3. Product MSRP set to 1200.00 - 30 pts
    4. Product Display Type set to 'In Cart' (Value 2) - 35 pts
    
    Pass threshold: 65 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_message = metadata.get('expected_message', "Add to cart to see our special low price!")
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_fn("/tmp/map_task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Global MAP Enabled (20 pts)
    global_enabled = str(result.get('global_map_enabled', '0')).strip()
    if global_enabled == '1':
        score += 20
        feedback_parts.append("Global MAP enabled (20 pts)")
    else:
        feedback_parts.append(f"Global MAP disabled (val={global_enabled})")

    # 2. Global Message (15 pts)
    global_message = result.get('global_map_message', '').strip()
    # Normalize spaces/case slightly for leniency
    if global_message.lower() == expected_message.lower():
        score += 15
        feedback_parts.append("Global explanation message correct (15 pts)")
    else:
        feedback_parts.append(f"Global message incorrect: '{global_message}' (Expected: '{expected_message}')")

    # 3. Product MSRP (30 pts)
    product_found = result.get('product_found', False)
    if not product_found:
        feedback_parts.append("Product LAPTOP-001 not found")
    else:
        msrp_val = result.get('product_msrp', '')
        try:
            msrp_float = float(msrp_val)
            if abs(msrp_float - 1200.0) < 0.01:
                score += 30
                feedback_parts.append("Product MSRP set to 1200.00 (30 pts)")
            else:
                feedback_parts.append(f"Product MSRP incorrect: {msrp_val} (Expected: 1200.00)")
        except ValueError:
            feedback_parts.append(f"Product MSRP invalid/empty: {msrp_val}")

    # 4. Product Display Type (35 pts)
    # Value 2 = "In Cart" (Magento\Msrp\Model\Product\Attribute\Source\Type::TYPE_IN_CART)
    display_type = str(result.get('product_display_type', '')).strip()
    if display_type == '2':
        score += 35
        feedback_parts.append("Product display mode set to 'In Cart' (35 pts)")
    else:
        # Provide helpful feedback if they picked 'On Gesture' (1) or 'Before Order Confirmation' (3)
        msg_map = {'1': 'On Gesture', '3': 'Before Order Confirmation', '4': 'Use Config'}
        got_msg = msg_map.get(display_type, display_type)
        feedback_parts.append(f"Product display mode incorrect: {got_msg} (Expected: In Cart [2])")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }