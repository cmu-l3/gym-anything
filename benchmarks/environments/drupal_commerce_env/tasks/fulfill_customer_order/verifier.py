#!/usr/bin/env python3
"""Verifier for fulfill_customer_order task.

Scoring (100 points):
- Criterion 1: Order exists for correct customer (uid=3, janesmith) — 15 points
- Criterion 2: Order contains Sony WH-1000XM5 — 15 points
- Criterion 3: Order contains Logitech MX Master 3S — 15 points
- Criterion 4: WELCOME10 coupon applied with discount — 20 points
- Criterion 5: Billing address set with correct city/state — 15 points
- Criterion 6: Order is placed (not draft) — 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_fulfill_customer_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_uid = metadata.get('customer_uid', 3)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fulfill_customer_order_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: If no order found at all, no work was done
    if not result.get('order_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No order found for customer janesmith"
        }

    # CRITICAL: Wrong customer check
    actual_uid = result.get('order_uid')
    if actual_uid is not None and int(actual_uid) != expected_uid:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong customer! Expected uid={expected_uid}, got uid={actual_uid}"
        }

    # Criterion 1: Order exists for correct customer (15 pts)
    try:
        if result.get('order_found') and result.get('new_orders', 0) > 0:
            score += 15
            subscores["order_created"] = True
            feedback_parts.append("Order created for janesmith")
        else:
            feedback_parts.append("No new order detected")
    except Exception as e:
        feedback_parts.append(f"Order check error: {e}")

    # Criterion 2: Order contains Sony WH-1000XM5 (15 pts)
    try:
        if result.get('has_sony'):
            score += 15
            subscores["has_sony"] = True
            feedback_parts.append("Sony WH-1000XM5 in order")
        else:
            feedback_parts.append("Sony WH-1000XM5 NOT in order")
    except Exception as e:
        feedback_parts.append(f"Sony check error: {e}")

    # Criterion 3: Order contains Logitech MX Master 3S (15 pts)
    try:
        if result.get('has_logi'):
            score += 15
            subscores["has_logi"] = True
            feedback_parts.append("Logitech MX Master 3S in order")
        else:
            feedback_parts.append("Logitech MX Master 3S NOT in order")
    except Exception as e:
        feedback_parts.append(f"Logitech check error: {e}")

    # Criterion 4: Coupon applied with discount (20 pts)
    try:
        if result.get('has_coupon_applied') and result.get('has_discount'):
            score += 20
            subscores["coupon_applied"] = True
            discount = result.get('discount_amount', '0')
            feedback_parts.append(f"WELCOME10 coupon applied (discount: ${discount})")
        elif result.get('has_coupon_applied'):
            score += 10
            feedback_parts.append("Coupon applied but no discount adjustment found")
        else:
            feedback_parts.append("WELCOME10 coupon NOT applied")
    except Exception as e:
        feedback_parts.append(f"Coupon check error: {e}")

    # Criterion 5: Billing address set with correct city/state (15 pts)
    try:
        if result.get('has_billing_address'):
            billing_city = (result.get('billing_city') or '').lower()
            billing_state = (result.get('billing_state') or '').upper()

            if 'portland' in billing_city and billing_state == 'OR':
                score += 15
                subscores["billing_address"] = True
                feedback_parts.append("Billing address correct (Portland, OR)")
            elif result.get('has_billing_address'):
                score += 5
                feedback_parts.append(f"Billing address set but wrong location: {billing_city}, {billing_state}")
        else:
            feedback_parts.append("No billing address set")
    except Exception as e:
        feedback_parts.append(f"Billing check error: {e}")

    # Criterion 6: Order is placed / not draft (20 pts)
    try:
        if result.get('order_placed'):
            score += 20
            subscores["order_placed"] = True
            feedback_parts.append(f"Order placed (state: {result.get('order_state')})")
        else:
            state = result.get('order_state', 'unknown')
            feedback_parts.append(f"Order still in draft state: {state}")
    except Exception as e:
        feedback_parts.append(f"Order state check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
