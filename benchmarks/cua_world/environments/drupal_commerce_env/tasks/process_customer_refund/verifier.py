#!/usr/bin/env python3
"""Verifier for process_customer_refund task.

Scoring (100 points):
- Criterion 1: Order found and belongs to correct customer (johndoe, uid=2) — 10 points
- Criterion 2: Order state changed to 'canceled' — 25 points
- Criterion 3: Refund/store credit promotion created with correct amount — 25 points
- Criterion 4: REFUND-JOHNDOE coupon created and linked to promotion — 20 points
- Criterion 5: Promotion is active, requires coupon, assigned to store — 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_process_customer_refund(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_uid = metadata.get('customer_uid', 2)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/process_customer_refund_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: check if any work was done
    order_changed = result.get('order_canceled', False) or result.get('current_order_state') != result.get('initial_order_state')
    promo_created = result.get('refund_promo_found', False)
    if not order_changed and not promo_created:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected — order not canceled and no refund promotion created"
        }

    # Criterion 1: Order belongs to correct customer (10 pts)
    try:
        order_uid = result.get('order_uid')
        if order_uid is not None and int(order_uid) == expected_uid:
            score += 10
            subscores["correct_customer"] = True
            feedback_parts.append("Order belongs to johndoe (uid=2)")
        elif order_uid is not None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong customer! Expected uid={expected_uid}, got uid={order_uid}"
            }
        else:
            feedback_parts.append("Could not verify order customer")
    except Exception as e:
        feedback_parts.append(f"Customer check error: {e}")

    # Criterion 2: Order canceled (25 pts)
    try:
        if result.get('order_canceled'):
            score += 25
            subscores["order_canceled"] = True
            feedback_parts.append("Order canceled")
        else:
            current_state = result.get('current_order_state', 'unknown')
            feedback_parts.append(f"Order NOT canceled (state: {current_state})")
    except Exception as e:
        feedback_parts.append(f"Order state check error: {e}")

    # Criterion 3: Refund promotion with correct amount (25 pts)
    try:
        if result.get('refund_promo_found'):
            promo_name = result.get('refund_promo_name', '')
            offer_type = result.get('refund_promo_offer_type', '')
            refund_amount_str = result.get('refund_amount', '')

            # Check it's a fixed amount off
            if 'fixed_amount' in offer_type:
                try:
                    refund_amount = float(refund_amount_str) if refund_amount_str else 0
                    expected_amount = metadata.get('expected_refund_amount', 1298.00)
                    if abs(refund_amount - expected_amount) < 1.0:
                        score += 25
                        subscores["refund_amount"] = True
                        feedback_parts.append(f"Refund promotion created: ${refund_amount:.2f}")
                    elif refund_amount > 0:
                        score += 10
                        feedback_parts.append(f"Refund promo created but amount ${refund_amount:.2f} != expected ${expected_amount:.2f}")
                    else:
                        score += 5
                        feedback_parts.append("Refund promo exists but amount is 0 or unreadable")
                except (ValueError, TypeError):
                    score += 5
                    feedback_parts.append(f"Refund promo exists but amount parse error: {refund_amount_str}")
            elif 'percentage' in offer_type:
                score += 5
                feedback_parts.append("Refund promo exists but uses percentage, should be fixed amount")
            else:
                score += 5
                feedback_parts.append(f"Refund promo exists (type: {offer_type})")
        else:
            feedback_parts.append("No refund/store credit promotion found")
    except Exception as e:
        feedback_parts.append(f"Refund promo check error: {e}")

    # Criterion 4: REFUND-JOHNDOE coupon linked (20 pts)
    try:
        if result.get('coupon_found') and result.get('coupon_code', '').upper() == 'REFUND-JOHNDOE':
            if result.get('coupon_linked'):
                usage_limit = int(result.get('coupon_usage_limit', 0))
                if usage_limit == 1:
                    score += 20
                    subscores["coupon_correct"] = True
                    feedback_parts.append("REFUND-JOHNDOE coupon linked with usage limit=1")
                else:
                    score += 15
                    feedback_parts.append(f"REFUND-JOHNDOE coupon linked but usage limit={usage_limit} (expected 1)")
            else:
                score += 10
                feedback_parts.append("REFUND-JOHNDOE coupon exists but not linked to promotion")
        elif result.get('coupon_found'):
            score += 5
            feedback_parts.append(f"Coupon found but code is '{result.get('coupon_code')}' (expected REFUND-JOHNDOE)")
        else:
            feedback_parts.append("REFUND-JOHNDOE coupon not found")
    except Exception as e:
        feedback_parts.append(f"Coupon check error: {e}")

    # Criterion 5: Promotion active, requires coupon, store assigned (20 pts)
    try:
        promo_status = int(result.get('refund_promo_status', 0))
        require_coupon = int(result.get('refund_promo_require_coupon', 0))
        store_assigned = result.get('store_assigned', False)

        config_score = 0
        if promo_status == 1:
            config_score += 7
        if require_coupon == 1:
            config_score += 7
        if store_assigned:
            config_score += 6

        score += config_score
        if config_score == 20:
            subscores["promo_config"] = True
            feedback_parts.append("Promotion: active, requires coupon, store assigned")
        else:
            parts = []
            if promo_status != 1:
                parts.append("not active")
            if require_coupon != 1:
                parts.append("doesn't require coupon")
            if not store_assigned:
                parts.append("not assigned to store")
            feedback_parts.append(f"Promotion config issues: {', '.join(parts)}")
    except Exception as e:
        feedback_parts.append(f"Promo config check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
