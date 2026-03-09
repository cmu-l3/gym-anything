#!/usr/bin/env python3
"""Verifier for Customer Config B2B task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_customer_config(traj, env_info, task_info):
    """
    Verify Customer Configuration settings.

    Criteria (Total 100 pts):
    1. Address Lines = 3 (15 pts)
    2. Tax/VAT = Required ('req') (20 pts)
    3. Date of Birth = Required ('req') (20 pts)
    4. Email Sender = Customer Support ('support') (15 pts)
    5. Min Password Length = 10 (15 pts)
    6. Required Character Classes = 4 (15 pts)

    Pass threshold: 65 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_street_lines = metadata.get('expected_street_lines', '3')
    expected_taxvat_show = metadata.get('expected_taxvat_show', 'req')
    expected_dob_show = metadata.get('expected_dob_show', 'req')
    expected_email_identity = metadata.get('expected_email_identity', 'support')
    expected_min_password_length = metadata.get('expected_min_password_length', '10')
    expected_required_character_classes = metadata.get('expected_required_character_classes', '4')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/customer_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    config = result.get('config', {})
    score = 0
    feedback_parts = []

    # 1. Address Lines
    val_street = str(config.get('street_lines', '')).strip()
    if val_street == expected_street_lines:
        score += 15
        feedback_parts.append("Address lines set to 3 (15 pts)")
    else:
        feedback_parts.append(f"Address lines incorrect (expected 3, got '{val_street}')")

    # 2. Tax/VAT Show
    val_tax = str(config.get('taxvat_show', '')).strip()
    if val_tax == expected_taxvat_show:
        score += 20
        feedback_parts.append("Tax/VAT set to Required (20 pts)")
    elif val_tax == 'opt':
        feedback_parts.append("Tax/VAT set to Optional, expected Required")
    else:
        feedback_parts.append(f"Tax/VAT incorrect (expected 'req', got '{val_tax}')")

    # 3. DOB Show
    val_dob = str(config.get('dob_show', '')).strip()
    if val_dob == expected_dob_show:
        score += 20
        feedback_parts.append("Date of Birth set to Required (20 pts)")
    elif val_dob == 'opt':
        feedback_parts.append("Date of Birth set to Optional, expected Required")
    else:
        feedback_parts.append(f"Date of Birth incorrect (expected 'req', got '{val_dob}')")

    # 4. Email Sender
    val_email = str(config.get('email_identity', '')).strip()
    if val_email == expected_email_identity:
        score += 15
        feedback_parts.append("Email sender set to Customer Support (15 pts)")
    elif val_email == 'general':
        feedback_parts.append("Email sender left as General Contact")
    else:
        feedback_parts.append(f"Email sender incorrect (expected 'support', got '{val_email}')")

    # 5. Password Length
    val_pass = str(config.get('min_password_length', '')).strip()
    if val_pass == expected_min_password_length:
        score += 15
        feedback_parts.append("Min password length set to 10 (15 pts)")
    else:
        feedback_parts.append(f"Min password length incorrect (expected 10, got '{val_pass}')")

    # 6. Character Classes
    val_classes = str(config.get('required_character_classes_number', '')).strip()
    if val_classes == expected_required_character_classes:
        score += 15
        feedback_parts.append("Character classes set to 4 (15 pts)")
    else:
        feedback_parts.append(f"Character classes incorrect (expected 4, got '{val_classes}')")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }