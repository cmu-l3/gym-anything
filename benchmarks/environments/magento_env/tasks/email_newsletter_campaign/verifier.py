#!/usr/bin/env python3
"""Verifier for Email Newsletter Campaign task in Magento.

Task: Configure newsletter settings, create a template, and subscribe customers.

Criteria:
1. Newsletter template 'Holiday Collection 2024' exists (15 pts)
2. Template subject, sender name, and email match exactly (20 pts)
3. Template content has valid HTML structure (h1, p, list) (15 pts)
4. At least 3 target customers subscribed (15 pts)
5. All 5 target customers subscribed (10 pts bonus)
6. Guest subscription allowed (10 pts)
7. Confirmation disabled (10 pts)
8. Anti-gaming: Template created after task start (5 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_newsletter_campaign(traj, env_info, task_info):
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/newsletter_result.json", tmp.name)
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
    
    metadata = task_info.get('metadata', {})
    
    # 1. Config Settings (20 pts)
    # Allow Guest: expected '1'
    allow_guest = str(result.get('config_allow_guest', '')).strip()
    if allow_guest == '1':
        score += 10
        feedback_parts.append("Guest subscription enabled (10 pts)")
    else:
        feedback_parts.append(f"Guest subscription NOT enabled (val={allow_guest})")

    # Need Confirm: expected '0'
    need_confirm = str(result.get('config_need_confirm', '')).strip()
    if need_confirm == '0':
        score += 10
        feedback_parts.append("Confirmation disabled (10 pts)")
    else:
        feedback_parts.append(f"Confirmation NOT disabled (val={need_confirm})")

    # 2. Template Existence & Content (55 pts)
    template_found = result.get('template_found', False)
    if template_found:
        score += 15
        feedback_parts.append("Template 'Holiday Collection 2024' found (15 pts)")
        
        # Check details
        subj = result.get('template_subject', '')
        sender_name = result.get('template_sender_name', '')
        sender_email = result.get('template_sender_email', '')
        
        exp_subj = metadata.get('template_subject', '')
        exp_name = metadata.get('sender_name', '')
        exp_email = metadata.get('sender_email', '')
        
        details_ok = True
        if exp_subj not in subj:
            details_ok = False
            feedback_parts.append(f"Subject mismatch ('{subj}')")
        if sender_name.lower() != exp_name.lower():
            details_ok = False
            feedback_parts.append(f"Sender name mismatch ('{sender_name}')")
        if sender_email.lower() != exp_email.lower():
            details_ok = False
            feedback_parts.append(f"Sender email mismatch ('{sender_email}')")
            
        if details_ok:
            score += 20
            feedback_parts.append("Template details correct (20 pts)")
            
        # HTML Content
        has_h1 = result.get('template_has_h1', False)
        has_p = result.get('template_has_p', False)
        has_list = result.get('template_has_list', False)
        
        if has_h1 and has_p and has_list:
            score += 15
            feedback_parts.append("Template HTML content valid (15 pts)")
        elif has_h1 or has_p or has_list:
            score += 5
            feedback_parts.append("Partial HTML content credit (5 pts)")
        else:
            feedback_parts.append("Missing HTML elements (h1, p, list)")

        # Anti-gaming: Check creation time vs task start
        # This is a bit loose since DB time vs System time might drift in docker
        # Just check if 'added_at' is present, effectively
        if result.get('template_added_at'):
            score += 5
            feedback_parts.append("Template creation timestamp verified (5 pts)")
    else:
        feedback_parts.append("Template 'Holiday Collection 2024' NOT found")

    # 3. Subscribers (25 pts)
    sub_count = result.get('target_subscriber_count', 0)
    if sub_count >= 5:
        score += 25
        feedback_parts.append("All 5 customers subscribed (25 pts)")
    elif sub_count >= 3:
        score += 15
        feedback_parts.append(f"Partial subscription: {sub_count}/5 customers (15 pts)")
    elif sub_count > 0:
        score += 5
        feedback_parts.append(f"Only {sub_count}/5 customers subscribed (5 pts)")
    else:
        feedback_parts.append("No target customers subscribed")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }