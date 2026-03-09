#!/usr/bin/env python3
"""Verifier for setup_store_tax_configuration task.

Scoring (100 points):
- Criterion 1: Store timezone updated to America/Los_Angeles — 20 points
- Criterion 2: US added to store tax registrations — 20 points
- Criterion 3: Store address updated to '100 Commerce Boulevard' — 20 points
- Criterion 4: taxmanager user created with correct email — 20 points
- Criterion 5: commerce_tax module enabled and currency is USD — 20 points

Pass threshold: 60 points (3 of 5 subtasks)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_setup_store_tax_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_store_tax_configuration_result.json", temp_file.name)
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

    # GATE: check if any changes were made
    any_change = (
        result.get('timezone_changed') or
        result.get('address_changed') or
        result.get('tax_user_found') or
        int(result.get('current_tax_registrations', 0)) > int(result.get('initial_tax_registrations', 0))
    )
    if not any_change:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected — no work was done"
        }

    # Criterion 1: Timezone updated to America/Los_Angeles (20 pts)
    try:
        current_tz = result.get('current_timezone', '')
        expected_tz = metadata.get('expected_timezone', 'America/Los_Angeles')

        if current_tz == expected_tz:
            score += 20
            subscores["timezone"] = True
            feedback_parts.append(f"Timezone set to {current_tz}")
        elif current_tz != result.get('initial_timezone', 'UTC'):
            score += 5
            feedback_parts.append(f"Timezone changed to '{current_tz}' (expected '{expected_tz}')")
        else:
            feedback_parts.append(f"Timezone unchanged: {current_tz}")
    except Exception as e:
        feedback_parts.append(f"Timezone check error: {e}")

    # Criterion 2: US added to tax registrations (20 pts)
    try:
        tax_countries = result.get('tax_reg_countries', '')
        current_regs = int(result.get('current_tax_registrations', 0))

        if 'US' in tax_countries.upper():
            score += 20
            subscores["tax_registration"] = True
            feedback_parts.append("US added to tax registrations")
        elif current_regs > int(result.get('initial_tax_registrations', 0)):
            score += 10
            feedback_parts.append(f"Tax registrations added but not US: {tax_countries}")
        else:
            feedback_parts.append("No tax registrations added")
    except Exception as e:
        feedback_parts.append(f"Tax registration check error: {e}")

    # Criterion 3: Store address updated (20 pts)
    try:
        current_addr = result.get('current_address', '')
        expected_addr = metadata.get('expected_address_line1', '100 Commerce Boulevard')

        if expected_addr.lower() in current_addr.lower() or current_addr.lower() in expected_addr.lower():
            score += 20
            subscores["address"] = True
            feedback_parts.append(f"Address updated to '{current_addr}'")
        elif result.get('address_changed'):
            score += 5
            feedback_parts.append(f"Address changed to '{current_addr}' (expected '{expected_addr}')")
        else:
            feedback_parts.append(f"Address unchanged: {current_addr}")
    except Exception as e:
        feedback_parts.append(f"Address check error: {e}")

    # Criterion 4: taxmanager user created (20 pts)
    try:
        if result.get('tax_user_found'):
            user_email = result.get('tax_user_email', '')
            expected_email = metadata.get('expected_new_email', 'tax@urbanelectronics.com')

            if user_email.lower() == expected_email.lower():
                score += 20
                subscores["tax_user"] = True
                feedback_parts.append("taxmanager user created with correct email")
            else:
                score += 10
                feedback_parts.append(f"taxmanager created but email is '{user_email}' (expected '{expected_email}')")
        else:
            feedback_parts.append("taxmanager user not found")
    except Exception as e:
        feedback_parts.append(f"User check error: {e}")

    # Criterion 5: commerce_tax enabled and currency is USD (20 pts)
    try:
        tax_enabled = result.get('tax_module_enabled', False)
        currency = result.get('current_currency', '')

        pts = 0
        if tax_enabled:
            pts += 10
        if currency == 'USD':
            pts += 10

        score += pts
        if pts == 20:
            subscores["tax_module_currency"] = True
            feedback_parts.append("commerce_tax enabled, currency is USD")
        else:
            parts = []
            if not tax_enabled:
                parts.append("commerce_tax not enabled")
            if currency != 'USD':
                parts.append(f"currency is {currency} not USD")
            feedback_parts.append(" | ".join(parts))
    except Exception as e:
        feedback_parts.append(f"Module/currency check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
