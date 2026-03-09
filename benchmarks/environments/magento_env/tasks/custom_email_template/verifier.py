#!/usr/bin/env python3
"""Verifier for Custom Email Template task in Magento.

Task: Create 'NestWell Order Confirmation' email template based on 'New Order',
customize subject and content, and assign it in store configuration.

Scoring Criteria (100 pts total):
1. Template exists with correct name (20 pts)
2. Template based on 'New Order' default (10 pts)
3. Subject line contains brand and order ID variable (15 pts)
4. Body content contains brand name (10 pts)
5. Body content contains support email (10 pts)
6. Body content preserves order ID variable (10 pts)
7. Store configuration updated to use this template (25 pts)

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_email_template(traj, env_info, task_info):
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/email_template_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    logger.info(f"Verification Result Data: {result}")

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_template_name', "NestWell Order Confirmation")
    expected_orig_code = metadata.get('orig_template_code', "sales_email_order_template")
    
    # Check 1: Template Existence (20 pts)
    template_found = result.get('template_found', False)
    template_id = result.get('template_id', "")
    template_code = result.get('template_code', "")
    
    if template_found and template_code.lower().strip() == expected_name.lower().strip():
        score += 20
        feedback_parts.append(f"Template '{expected_name}' created (20 pts)")
    else:
        feedback_parts.append(f"Template '{expected_name}' NOT found")
        # If template not found, we can't check content, but can check config (unlikely to be correct though)
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Original Template Source (10 pts)
    orig_code = result.get('orig_template_code', "")
    if orig_code == expected_orig_code:
        score += 10
        feedback_parts.append("Based on correct default template (10 pts)")
    else:
        feedback_parts.append(f"Wrong base template (expected {expected_orig_code}, got {orig_code})")

    # Check 3: Subject Line (15 pts)
    # Expected: "Your NestWell Home Order #{{var order.increment_id}} - Thank You!"
    subject = result.get('template_subject', "")
    subject_part1 = metadata.get('expected_subject_part1', "NestWell Home")
    subject_part2 = metadata.get('expected_subject_part2', "{{var order.increment_id}}")
    
    if subject_part1 in subject and subject_part2 in subject:
        score += 15
        feedback_parts.append("Subject line correct (15 pts)")
    elif subject_part1 in subject or subject_part2 in subject:
        score += 7
        feedback_parts.append("Subject line partially correct (7 pts)")
    else:
        feedback_parts.append("Subject line missing required elements")

    # Check 4: Body Content - Brand (10 pts)
    if result.get('content_has_brand', False):
        score += 10
        feedback_parts.append("Body contains brand name (10 pts)")
    else:
        feedback_parts.append("Body missing brand name")

    # Check 5: Body Content - Email (10 pts)
    if result.get('content_has_email', False):
        score += 10
        feedback_parts.append("Body contains support email (10 pts)")
    else:
        feedback_parts.append("Body missing support email")

    # Check 6: Body Content - Variable (10 pts)
    if result.get('content_has_var', False):
        score += 10
        feedback_parts.append("Body preserves order ID variable (10 pts)")
    else:
        feedback_parts.append("Body missing order ID variable")

    # Check 7: Configuration (25 pts)
    # The config value in core_config_data should match the template_id
    current_config = str(result.get('current_config_value', "")).strip()
    target_id = str(template_id).strip()
    
    if current_config == target_id:
        score += 25
        feedback_parts.append("Store configuration updated correctly (25 pts)")
    else:
        feedback_parts.append(f"Store config not updated (expected ID {target_id}, got '{current_config}')")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }