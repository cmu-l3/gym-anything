#!/usr/bin/env python3
"""Verifier for Customer Attribute task in Magento.

Task: Create custom customer attribute 'skin_concern' (dropdown, required,
visible on storefront) with 5 specific option values.

Scored on 5 criteria (100 pts). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_OPTIONS = [
    "acne",           # matches "Acne & Blemishes"
    "anti-aging",     # matches "Anti-Aging"
    "hyperpigmentation",
    "dryness",        # matches "Dryness & Dehydration"
    "sensitivity",    # matches "Sensitivity"
]


def verify_customer_attribute(traj, env_info, task_info):
    """
    Verify custom customer attribute creation.

    Criteria:
    1. Attribute 'skin_concern' exists in customer entity type (20 pts)
    2. Attribute is a dropdown (frontend_input = 'select') (20 pts)
    3. At least 4 of 5 required option values are present (25 pts)
    4. Attribute is marked as Required (is_required = 1) (20 pts)
    5. Attribute is visible on storefront / in customer forms (15 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/customer_attribute_result.json", tmp.name)
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

    # ── GATE: Attribute must exist ────────────────────────────────────────────
    attr_found = result.get('attr_found', False)
    attr_code = result.get('attribute_code', '').strip().lower()

    if not attr_found or attr_code != 'skin_concern':
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Customer attribute 'skin_concern' not found. "
                        "Navigate to Stores > Attributes > Customer and create it.",
            "subscores": {
                "attr_exists": False, "is_dropdown": False,
                "options_complete": False, "is_required": False,
                "is_visible": False
            }
        }

    # ── Criterion 1: Attribute exists with correct code (20 pts) ─────────────
    score += 20
    feedback_parts.append("Attribute 'skin_concern' exists in customer entity (20 pts)")
    subscores['attr_exists'] = True

    # ── Criterion 2: Attribute type is dropdown/select (20 pts) ──────────────
    frontend_input = result.get('frontend_input', '').strip().lower()
    is_dropdown = frontend_input in ('select', 'dropdown')
    if is_dropdown:
        score += 20
        feedback_parts.append("Attribute type is dropdown/select (20 pts)")
    else:
        feedback_parts.append(
            f"Attribute input type should be 'select' (dropdown), got '{frontend_input}'"
        )
    subscores['is_dropdown'] = is_dropdown

    # ── Criterion 3: At least 4 of 5 required option values present (25 pts) ─
    required_found = int(result.get('required_options_found', 0))
    option_count = int(result.get('option_count', 0))
    option_values = result.get('option_values', '').lower()

    # Double-check by scanning option values string directly
    found_count = sum(1 for kw in REQUIRED_OPTIONS if kw in option_values)
    required_found = max(required_found, found_count)

    if required_found >= 5:
        score += 25
        feedback_parts.append(f"All 5 required skin concern options present (25 pts)")
    elif required_found >= 4:
        score += 18
        feedback_parts.append(
            f"4 of 5 required options found (18 pts). Check missing option."
        )
    elif required_found >= 3:
        score += 10
        feedback_parts.append(
            f"Only {required_found}/5 required options found (10 pts partial). "
            f"Missing options from: Acne & Blemishes, Anti-Aging, Hyperpigmentation, "
            f"Dryness & Dehydration, Sensitivity"
        )
    else:
        feedback_parts.append(
            f"Only {required_found}/5 required option values found. "
            f"Add all 5: Acne & Blemishes, Anti-Aging, Hyperpigmentation, "
            f"Dryness & Dehydration, Sensitivity"
        )
    subscores['options_complete'] = (required_found >= 4)

    # ── Criterion 4: Attribute is Required (20 pts) ───────────────────────────
    is_required_str = str(result.get('is_required', '0')).strip()
    is_required = is_required_str in ('1', 'true', 'True')
    if is_required:
        score += 20
        feedback_parts.append("Attribute is marked as Required (20 pts)")
    else:
        feedback_parts.append(
            "Attribute is NOT set as Required. Set 'Values Required' to Yes."
        )
    subscores['is_required'] = is_required

    # ── Criterion 5: Visible on storefront / in forms (15 pts) ────────────────
    is_visible_str = str(result.get('is_visible', '0')).strip()
    is_visible_on_front_str = str(result.get('is_visible_on_front', '0')).strip()
    in_reg_form = result.get('in_registration_form', False)
    in_acct_form = result.get('in_account_edit_form', False)
    used_in_forms = result.get('used_in_forms', '')

    visible_on_front = is_visible_on_front_str in ('1', 'true', 'True')
    visible = is_visible_str in ('1', 'true', 'True')
    in_any_form = in_reg_form or in_acct_form or bool(used_in_forms)

    storefront_ok = visible_on_front or (visible and in_any_form)
    if storefront_ok:
        score += 15
        feedback_parts.append("Attribute is visible on storefront / in customer forms (15 pts)")
    elif in_any_form:
        score += 8
        feedback_parts.append(
            f"Attribute is in some forms ({used_in_forms}) but not flagged as visible on front (8 pts)"
        )
    else:
        feedback_parts.append(
            "Attribute is NOT visible on storefront. Enable 'Show on Storefront' and add to "
            "Customer Registration and Customer Account Edit forms."
        )
    subscores['is_visible'] = storefront_ok

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
