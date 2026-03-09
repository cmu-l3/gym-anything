#!/usr/bin/env python3
"""Verifier for Minimum Order Policy task in Magento.

Task: Configure Minimum Order Amount to $35.00, enabled, include tax=Yes,
exclude discount=No, and set specific error messages.

Scored on 6 criteria (100 pts total). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_min_order_policy(traj, env_info, task_info):
    """
    Verify Minimum Order Policy configuration.

    Criteria:
    1. Feature is Enabled (sales/minimum_order/active = 1) (20 pts)
    2. Amount is 35.00 (20 pts)
    3. Tax Inclusion is Yes (1) (15 pts)
    4. Discount Inclusion is No (0) (15 pts)
    5. Description message contains expected text (15 pts)
    6. Cart Error message contains expected text (15 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/min_order_result.json", tmp.name)
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

    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('expected_description', 'at least $35.00').lower()
    expected_error = metadata.get('expected_error', 'under $35.00').lower()

    score = 0
    feedback_parts = []

    # 1. Feature Enabled (20 pts)
    active = str(result.get('config_active', '0')).strip()
    if active == '1':
        score += 20
        feedback_parts.append("Minimum Order is Active (20 pts)")
    else:
        feedback_parts.append("Minimum Order NOT Active (0 pts)")

    # 2. Correct Amount (20 pts)
    amount_str = str(result.get('config_amount', '0')).strip()
    try:
        amount = float(amount_str)
        if abs(amount - 35.0) < 0.01:
            score += 20
            feedback_parts.append("Minimum Amount is $35.00 (20 pts)")
        else:
            feedback_parts.append(f"Incorrect amount: ${amount} (expected $35.00)")
    except ValueError:
        feedback_parts.append(f"Invalid amount format: {amount_str}")

    # 3. Tax Inclusion Logic (15 pts) - Expected Yes (1)
    tax_include = str(result.get('config_tax_include', '0')).strip()
    if tax_include == '1':
        score += 15
        feedback_parts.append("Tax Inclusion correct (Yes) (15 pts)")
    else:
        feedback_parts.append(f"Tax Inclusion incorrect: got {tax_include}, expected Yes (1)")

    # 4. Discount Logic (15 pts) - Expected No (0)
    # Note: Magento stores 'No' as '0' or NULL (missing row). If missing, it defaults to No.
    # However, the task asked to Configure it. Usually explicit setting creates a row.
    # We will accept '0' or empty if the logic holds, but standard config save writes '0'.
    disc_include = str(result.get('config_discount_include', '0')).strip()
    if disc_include == '0':
        score += 15
        feedback_parts.append("Discount Inclusion correct (No) (15 pts)")
    else:
        feedback_parts.append(f"Discount Inclusion incorrect: got {disc_include}, expected No (0)")

    # 5. Description Message (15 pts)
    desc = str(result.get('config_description', '')).lower()
    if "at least $35.00" in desc or expected_desc in desc:
        score += 15
        feedback_parts.append("Description message correct (15 pts)")
    else:
        feedback_parts.append(f"Description message mismatch. Got: '{desc[:50]}...'")

    # 6. Error Message (15 pts)
    err = str(result.get('config_error_message', '')).lower()
    if "under $35.00" in err or expected_error in err:
        score += 15
        feedback_parts.append("Cart error message correct (15 pts)")
    else:
        feedback_parts.append(f"Error message mismatch. Got: '{err[:50]}...'")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }