#!/usr/bin/env python3
"""
Verifier for Admin Phone Order task in Magento.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_admin_phone_order(traj, env_info, task_info):
    """
    Verify that the admin created the phone order correctly.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_fn("/tmp/admin_order_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Check if order exists and was created during task (Gatekeeper)
    if not result.get('order_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No order found for alice.williams@example.com."
        }
    
    if not result.get('created_during_task'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Order found, but it was created before the task started (pre-existing)."
        }

    score += 10
    feedback_parts.append("New order created (10 pts)")

    # 2. Verify Customer (Implicit in query, but double check)
    if result.get('customer_email') == 'alice.williams@example.com':
        score += 15
        feedback_parts.append("Correct customer selected (15 pts)")
    else:
        feedback_parts.append(f"Wrong customer: {result.get('customer_email')}")

    # 3. Verify Items (35 pts total)
    # Expected: HEADPHONES-001 (qty 2), LAMP-001 (qty 1)
    items = result.get('items', [])
    headphones = next((i for i in items if i['sku'] == 'HEADPHONES-001'), None)
    lamp = next((i for i in items if i['sku'] == 'LAMP-001'), None)

    if headphones:
        qty = float(headphones['qty'])
        if qty == 2.0:
            score += 20
            feedback_parts.append("Headphones Qty 2 correct (20 pts)")
        else:
            score += 5
            feedback_parts.append(f"Headphones found but wrong Qty: {qty} (5 pts)")
    else:
        feedback_parts.append("Headphones missing from order")

    if lamp:
        qty = float(lamp['qty'])
        if qty == 1.0:
            score += 15
            feedback_parts.append("Lamp Qty 1 correct (15 pts)")
        else:
            score += 5
            feedback_parts.append(f"Lamp found but wrong Qty: {qty} (5 pts)")
    else:
        feedback_parts.append("Lamp missing from order")

    # 4. Verify Shipping Address (15 pts)
    addr = result.get('shipping_address', {})
    # Loose matching to be forgiving of case/spacing
    addr_match = True
    if 'Emily' not in addr.get('firstname', ''): addr_match = False
    if 'Carter' not in addr.get('lastname', ''): addr_match = False
    if 'Portland' not in addr.get('city', ''): addr_match = False
    if '97201' not in addr.get('postcode', ''): addr_match = False
    
    if addr_match:
        score += 15
        feedback_parts.append("Shipping address correct (15 pts)")
    else:
        feedback_parts.append(f"Shipping address mismatch: {addr}")

    # 5. Verify Payment Method (10 pts)
    method = result.get('payment_method', '')
    if method == 'checkmo':
        score += 10
        feedback_parts.append("Payment method Check/Money Order correct (10 pts)")
    else:
        feedback_parts.append(f"Wrong payment method: {method}")

    # 6. Verify Grand Total (15 pts)
    # $299.98 + $34.99 + $5.00 (flat rate) = $339.97
    # Allow small tolerance
    try:
        total = float(result.get('grand_total', 0))
        if 334.00 <= total <= 345.00:
            score += 15
            feedback_parts.append(f"Grand total ${total} correct (15 pts)")
        else:
            feedback_parts.append(f"Grand total ${total} incorrect (expected ~$339.97)")
    except:
        feedback_parts.append("Could not parse grand total")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }