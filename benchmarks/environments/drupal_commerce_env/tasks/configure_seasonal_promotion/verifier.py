#!/usr/bin/env python3
"""Verifier for configure_seasonal_promotion task.

Scoring (100 points):
- Criterion 1: Promotion exists with correct name and is active — 15 points
- Criterion 2: Offer type is percentage off at 30% — 20 points
- Criterion 3: SPRING30 coupon created and linked to promotion — 20 points
- Criterion 4: Minimum order condition ($150+) configured — 20 points
- Criterion 5: Promotion requires coupon and coupon has usage limit of 50 — 10 points
- Criterion 6: Promotion assigned to Urban Electronics store — 15 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_seasonal_promotion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_seasonal_promotion_result.json", temp_file.name)
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

    # GATE: No promotion found = no work done
    if not result.get('promotion_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Spring Clearance promotion found"
        }

    # Criterion 1: Promotion exists, active, correct name (15 pts)
    try:
        promo_name = result.get('promotion_name', '')
        promo_status = result.get('promotion_status', 0)

        if 'spring clearance' in promo_name.lower() and '30' in promo_name:
            if int(promo_status) == 1:
                score += 15
                subscores["promotion_active"] = True
                feedback_parts.append(f"Promotion '{promo_name}' is active")
            else:
                score += 5
                feedback_parts.append(f"Promotion '{promo_name}' exists but is not active")
        else:
            feedback_parts.append(f"Promotion name mismatch: '{promo_name}'")
    except Exception as e:
        feedback_parts.append(f"Promotion name check error: {e}")

    # Criterion 2: Offer type is percentage off at 30% (20 pts)
    try:
        offer_type = result.get('promotion_offer_type', '')
        offer_pct = result.get('offer_percentage', '')

        if 'percentage' in offer_type.lower():
            try:
                pct_val = float(offer_pct) if offer_pct else 0
                if abs(pct_val - 0.30) < 0.01:
                    score += 20
                    subscores["offer_correct"] = True
                    feedback_parts.append("30% percentage discount configured")
                elif 0.01 < pct_val <= 1.0:
                    score += 10
                    feedback_parts.append(f"Percentage discount set but wrong value: {pct_val}")
                else:
                    score += 5
                    feedback_parts.append(f"Percentage offer type but value unclear: {offer_pct}")
            except (ValueError, TypeError):
                score += 5
                feedback_parts.append(f"Percentage offer but could not parse value: {offer_pct}")
        else:
            feedback_parts.append(f"Wrong offer type: {offer_type}")
    except Exception as e:
        feedback_parts.append(f"Offer check error: {e}")

    # Criterion 3: SPRING30 coupon created and linked (20 pts)
    try:
        coupon_found = result.get('coupon_found', False)
        coupon_code = result.get('coupon_code', '')
        coupon_linked = result.get('coupon_linked_to_promotion', False)

        if coupon_found and coupon_code.upper() == 'SPRING30':
            if coupon_linked:
                score += 20
                subscores["coupon_linked"] = True
                feedback_parts.append("SPRING30 coupon created and linked to promotion")
            else:
                score += 10
                feedback_parts.append("SPRING30 coupon exists but not linked to promotion")
        elif coupon_found:
            score += 5
            feedback_parts.append(f"Coupon found but code is '{coupon_code}' not SPRING30")
        else:
            feedback_parts.append("SPRING30 coupon not found")
    except Exception as e:
        feedback_parts.append(f"Coupon check error: {e}")

    # Criterion 4: Minimum order condition $150+ (20 pts)
    try:
        has_condition = result.get('has_min_order_condition', False)
        min_amount = result.get('min_order_amount', '')

        if has_condition:
            try:
                amount_val = float(min_amount) if min_amount else 0
                if abs(amount_val - 150.0) < 1.0:
                    score += 20
                    subscores["min_order_condition"] = True
                    feedback_parts.append("Min order condition: $150.00")
                elif amount_val > 0:
                    score += 10
                    feedback_parts.append(f"Min order condition set but wrong amount: ${amount_val}")
                else:
                    score += 5
                    feedback_parts.append("Min order condition exists but amount unclear")
            except (ValueError, TypeError):
                score += 5
                feedback_parts.append(f"Min order condition but parse error: {min_amount}")
        else:
            feedback_parts.append("No minimum order condition found")
    except Exception as e:
        feedback_parts.append(f"Condition check error: {e}")

    # Criterion 5: Require coupon + usage limit of 50 (10 pts)
    try:
        require_coupon = int(result.get('promotion_require_coupon', 0))
        coupon_limit = int(result.get('coupon_usage_limit', 0))

        if require_coupon == 1 and coupon_limit == 50:
            score += 10
            subscores["coupon_config"] = True
            feedback_parts.append("Require coupon=yes, usage limit=50")
        elif require_coupon == 1:
            score += 5
            feedback_parts.append(f"Require coupon=yes, but usage limit={coupon_limit} (expected 50)")
        else:
            feedback_parts.append("Promotion does not require coupon")
    except Exception as e:
        feedback_parts.append(f"Coupon config check error: {e}")

    # Criterion 6: Store assigned (15 pts)
    try:
        if result.get('store_assigned'):
            score += 15
            subscores["store_assigned"] = True
            feedback_parts.append("Promotion assigned to Urban Electronics store")
        else:
            feedback_parts.append("Promotion not assigned to store")
    except Exception as e:
        feedback_parts.append(f"Store check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
