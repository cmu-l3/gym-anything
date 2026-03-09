#!/usr/bin/env python3
"""Verifier for Support Tools Config task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_support_tools_config(traj, env_info, task_info):
    """
    Verify configuration of support tools.

    Criteria:
    1. Login as Customer is enabled (25 pts)
    2. Header Title is 'Assisted Service Mode' (25 pts)
    3. Online Interval is '5' (25 pts)
    4. Contact Email is 'support@luminarygadgets.com' (25 pts)

    Pass threshold: 75 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_lac_enabled = metadata.get('expected_login_as_customer_enabled', '1')
    expected_ui_title = metadata.get('expected_ui_title', 'Assisted Service Mode')
    expected_online_interval = metadata.get('expected_online_interval', '5')
    expected_contact_email = metadata.get('expected_contact_email', 'support@luminarygadgets.com')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/support_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []

    # Criterion 1: Login as Customer Enabled
    actual_lac_enabled = str(result.get('lac_enabled', '0')).strip()
    if actual_lac_enabled == expected_lac_enabled:
        score += 25
        feedback_parts.append("Login as Customer enabled (25 pts)")
    else:
        feedback_parts.append(f"Login as Customer NOT enabled (found: {actual_lac_enabled})")

    # Criterion 2: UI Title
    actual_ui_title = str(result.get('lac_title', '')).strip()
    # Case-insensitive check generally appropriate for text
    if actual_ui_title.lower() == expected_ui_title.lower():
        score += 25
        feedback_parts.append(f"UI Title correct: '{actual_ui_title}' (25 pts)")
    else:
        feedback_parts.append(f"UI Title incorrect: expected '{expected_ui_title}', got '{actual_ui_title}'")

    # Criterion 3: Online Interval
    actual_interval = str(result.get('online_interval', '')).strip()
    if actual_interval == expected_online_interval:
        score += 25
        feedback_parts.append(f"Online Interval correct: {actual_interval} min (25 pts)")
    else:
        feedback_parts.append(f"Online Interval incorrect: expected '{expected_online_interval}', got '{actual_interval}'")

    # Criterion 4: Contact Email
    actual_email = str(result.get('contact_email', '')).strip()
    if actual_email.lower() == expected_contact_email.lower():
        score += 25
        feedback_parts.append(f"Contact Email correct: {actual_email} (25 pts)")
    else:
        feedback_parts.append(f"Contact Email incorrect: expected '{expected_contact_email}', got '{actual_email}'")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }