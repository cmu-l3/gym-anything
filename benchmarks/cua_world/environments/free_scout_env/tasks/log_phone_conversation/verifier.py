#!/usr/bin/env python3
"""Verifier for log_phone_conversation task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_phone_conversation(traj, env_info, task_info):
    """
    Verify that a phone conversation was logged correctly.
    
    Key Success Criteria:
    1. A new conversation was created after task start.
    2. The conversation type is PHONE (type=2) - Critical!
    3. Subject and Body match expectations.
    4. Correct Mailbox and Customer selected.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_subject_keywords = ["Network Printer", "Not Detected", "HP LaserJet"]
    expected_body_keywords = metadata.get('expected_body_keywords', ["HP LaserJet", "192.168.1.45", "spooler"])
    expected_mailbox_name = metadata.get('expected_mailbox_name', "IT Support")
    expected_customer_email = metadata.get('expected_customer_email', "david.chen@acmecorp.com")

    # Read result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    conv = result.get('conversation', {})
    conv_id = conv.get('id')
    conv_type = conv.get('type')  # 1=Email, 2=Phone
    conv_subject = conv.get('subject', '')
    conv_body = conv.get('body', '')
    mailbox_name = conv.get('mailbox_name', '')
    customer_email = conv.get('customer_email', '')
    
    new_conv_diff = int(result.get('new_conv_diff', 0))
    
    # Criterion 1: New conversation created (15 points)
    if new_conv_diff > 0 and conv_id:
        score += 15
        feedback_parts.append("New conversation created")
    else:
        feedback_parts.append("No new conversation created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Type is Phone (30 points) - CRITICAL
    # In FreeScout DB: 1 = Email, 2 = Phone
    if str(conv_type) == "2":
        score += 30
        feedback_parts.append("Correct type (Phone/2)")
    elif str(conv_type) == "1":
        feedback_parts.append("Incorrect type: Created as Email (1) instead of Phone (2)")
    else:
        feedback_parts.append(f"Unknown conversation type: {conv_type}")

    # Criterion 3: Subject matches (15 points)
    subject_matches = 0
    for keyword in expected_subject_keywords:
        if keyword.lower() in conv_subject.lower():
            subject_matches += 1
    
    if subject_matches >= len(expected_subject_keywords) - 1: # Allow 1 missing
        score += 15
        feedback_parts.append("Subject matches")
    elif subject_matches > 0:
        score += 7
        feedback_parts.append(f"Subject partial match ('{conv_subject}')")
    else:
        feedback_parts.append(f"Subject mismatch ('{conv_subject}')")

    # Criterion 4: Body content (15 points)
    body_matches = 0
    for keyword in expected_body_keywords:
        if keyword.lower() in conv_body.lower():
            body_matches += 1
            
    if body_matches >= len(expected_body_keywords) - 1:
        score += 15
        feedback_parts.append(f"Body content matches ({body_matches} keywords)")
    elif body_matches > 0:
        score += 7
        feedback_parts.append(f"Body content partial match ({body_matches} keywords)")
    else:
        feedback_parts.append("Body content mismatch")

    # Criterion 5: Mailbox (15 points)
    if expected_mailbox_name.lower() in mailbox_name.lower():
        score += 15
        feedback_parts.append("Correct mailbox")
    else:
        feedback_parts.append(f"Wrong mailbox: expected '{expected_mailbox_name}', got '{mailbox_name}'")

    # Criterion 6: Customer (10 points)
    if expected_customer_email.lower() == customer_email.lower():
        score += 10
        feedback_parts.append("Correct customer")
    elif expected_customer_email.lower() in customer_email.lower():
        score += 5
        feedback_parts.append("Customer email partial match")
    else:
        feedback_parts.append(f"Wrong customer: expected '{expected_customer_email}', got '{customer_email}'")

    # Pass logic: Must have correct type AND >= 70 points
    passed = score >= 70 and str(conv_type) == "2"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }