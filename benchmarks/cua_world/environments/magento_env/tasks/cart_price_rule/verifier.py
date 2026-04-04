#!/usr/bin/env python3
"""Verifier for Cart Price Rule task in Magento.

Task: Create cart price rule 'BACK2SCHOOL25' with 25% discount for General
customer group, min subtotal $75, auto-generated coupons with B2S prefix (10 codes).

Scored on 5 independent criteria (100 pts total). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cart_price_rule(traj, env_info, task_info):
    """
    Verify cart price rule creation.

    Criteria:
    1. Rule 'BACK2SCHOOL25' exists in the database (20 pts)
    2. Discount is 25% (by_percent type, amount=25) (20 pts)
    3. At least 5 auto-generated coupon codes with B2S prefix exist (25 pts)
    4. Rule applies to General customer group only (20 pts)
    5. Minimum subtotal condition ($75) is set (15 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/cart_price_rule_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # ── GATE: Rule must exist ─────────────────────────────────────────────────
    rule_found = result.get('rule_found', False)
    if not rule_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Cart price rule 'BACK2SCHOOL25' not found in database. "
                        "Rule was not created or saved incorrectly.",
            "subscores": {
                "rule_exists": False, "discount_correct": False,
                "coupons_generated": False, "correct_customer_group": False,
                "subtotal_condition": False
            }
        }

    # ── Criterion 1: Rule exists with correct name (20 pts) ──────────────────
    rule_name = result.get('rule_name', '').strip().lower()
    name_ok = 'back2school25' in rule_name
    if name_ok:
        score += 20
        feedback_parts.append("Rule 'BACK2SCHOOL25' exists (20 pts)")
    else:
        feedback_parts.append(f"Rule name mismatch: got '{rule_name}'")
    subscores['rule_exists'] = name_ok

    # ── Criterion 2: Discount is 25% (20 pts) ────────────────────────────────
    discount_type = result.get('discount_type', '').strip().lower()
    discount_amount_str = result.get('discount_amount', '0')
    discount_correct = False
    try:
        amount = float(discount_amount_str) if discount_amount_str else 0.0
        type_ok = discount_type in ('by_percent', 'percent')
        amount_ok = abs(amount - 25.0) < 0.01
        discount_correct = type_ok and amount_ok
    except (ValueError, TypeError):
        pass

    if discount_correct:
        score += 20
        feedback_parts.append("Discount is 25% (by_percent type) (20 pts)")
    else:
        feedback_parts.append(
            f"Discount incorrect: expected type=by_percent amount=25, "
            f"got type='{discount_type}' amount='{discount_amount_str}'"
        )
    subscores['discount_correct'] = discount_correct

    # ── Criterion 3: At least 5 B2S-prefixed coupon codes exist (25 pts) ─────
    b2s_coupon_count = result.get('b2s_coupon_count', 0)
    coupon_total = result.get('coupon_total', 0)

    coupon_ok = b2s_coupon_count >= 5
    if b2s_coupon_count >= 10:
        score += 25
        feedback_parts.append(f"All 10 B2S coupon codes generated (25 pts)")
    elif b2s_coupon_count >= 5:
        score += 15
        feedback_parts.append(f"Partial: {b2s_coupon_count} B2S coupons found (need 10; 15 pts)")
    elif coupon_total >= 5:
        score += 5
        feedback_parts.append(
            f"Coupons exist ({coupon_total} total) but none/few have B2S prefix "
            f"(only {b2s_coupon_count} match). Regenerate with prefix 'B2S'."
        )
    else:
        feedback_parts.append(
            f"No coupon codes generated. Use 'Manage Coupon Codes' tab to generate 10 codes with prefix B2S."
        )
    subscores['coupons_generated'] = coupon_ok

    # ── Criterion 4: General customer group assigned (and ideally only General) (20 pts) ──
    general_assigned = result.get('general_group_assigned', False)
    non_general_assigned = result.get('non_general_group_assigned', False)

    if general_assigned and not non_general_assigned:
        score += 20
        feedback_parts.append("Rule correctly applies to General group only (20 pts)")
    elif general_assigned and non_general_assigned:
        score += 10
        feedback_parts.append(
            "Rule applies to General group but ALSO to other groups — should be General only (10 pts partial)"
        )
    else:
        feedback_parts.append("Rule does NOT apply to General customer group")
    subscores['correct_customer_group'] = general_assigned

    # ── Criterion 5: Minimum subtotal condition set (15 pts) ─────────────────
    has_subtotal = result.get('has_subtotal_condition', False)
    subtotal_value = result.get('subtotal_condition_value', '')

    if has_subtotal and subtotal_value == '75':
        score += 15
        feedback_parts.append("Minimum subtotal condition $75.00 set (15 pts)")
    elif has_subtotal:
        score += 8
        feedback_parts.append(
            f"Subtotal condition exists but value may not be $75 (partial 8 pts). Found value: '{subtotal_value}'"
        )
    else:
        feedback_parts.append(
            "No minimum subtotal condition found. Add condition: Subtotal >= $75 in the Conditions tab."
        )
    subscores['subtotal_condition'] = has_subtotal

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
