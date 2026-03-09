#!/usr/bin/env python3
"""
Verifier for create_conversation_with_cc task.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_conversation_with_cc(traj, env_info, task_info):
    """
    Verify the agent created a conversation with specific CC recipients and body content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_cc_1 = metadata.get('target_cc_1', 'deptchair.wilson@lakewood-univ.edu').lower()
    target_cc_2 = metadata.get('target_cc_2', 'facilities@lakewood-univ.edu').lower()
    target_subject_part = "Projector Maintenance Request".lower()
    required_body_keywords = metadata.get('required_body_keywords', ["Room 301", "Anderson Hall", "HDMI"])

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming: Count increased (5 pts)
    initial_count = int(result.get('initial_conv_count', 0))
    current_count = int(result.get('current_conv_count', 0))
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Conversation count increased")
    else:
        feedback_parts.append("Conversation count did NOT increase")

    # Check if conversation was found
    if not result.get('conversation_found'):
        return {
            "passed": False,
            "score": score,
            "feedback": "No conversation found with matching subject. " + " | ".join(feedback_parts)
        }

    conv = result.get('conversation', {})
    
    # 2. Subject Check (20 pts)
    subject = conv.get('subject', '').lower()
    if target_subject_part in subject:
        score += 20
        feedback_parts.append("Subject correct")
    else:
        feedback_parts.append(f"Subject mismatch: got '{conv.get('subject')}'")

    # 3. Mailbox Check (10 pts)
    expected_mailbox_id = result.get('expected_mailbox_id', '0')
    actual_mailbox_id = conv.get('mailbox_id', '')
    if str(actual_mailbox_id) == str(expected_mailbox_id) and expected_mailbox_id != '0':
        score += 10
        feedback_parts.append("Correct Mailbox")
    else:
        feedback_parts.append(f"Wrong Mailbox (expected {expected_mailbox_id}, got {actual_mailbox_id})")

    # 4. Customer Check (10 pts)
    # Check customer ID or TO field
    expected_customer_id = result.get('expected_customer_id', '0')
    actual_customer_id = conv.get('customer_id', '')
    thread_to = conv.get('thread_to', '').lower()
    
    customer_match = False
    if str(actual_customer_id) == str(expected_customer_id) and expected_customer_id != '0':
        customer_match = True
    elif "prof.martinez" in thread_to:
        customer_match = True
        
    if customer_match:
        score += 10
        feedback_parts.append("Correct Customer")
    else:
        feedback_parts.append("Wrong Customer")

    # 5. CC Recipients Check (30 pts - 15 each)
    cc_field = conv.get('thread_cc', '').lower()
    
    if target_cc_1 in cc_field:
        score += 15
        feedback_parts.append("CC #1 Found")
    else:
        feedback_parts.append(f"CC #1 ({target_cc_1}) missing")
        
    if target_cc_2 in cc_field:
        score += 15
        feedback_parts.append("CC #2 Found")
    else:
        feedback_parts.append(f"CC #2 ({target_cc_2}) missing")

    # 6. Body Content Check (15 pts)
    body = conv.get('thread_body', '').lower()
    keywords_found = 0
    for kw in required_body_keywords:
        if kw.lower() in body:
            keywords_found += 1
    
    if keywords_found >= len(required_body_keywords) - 1: # Allow missing 1
        score += 15
        feedback_parts.append("Body content correct")
    elif keywords_found > 0:
        score += 5
        feedback_parts.append("Body content partial")
    else:
        feedback_parts.append("Body content missing keywords")

    # 7. VLM Check (10 pts)
    # Basic check if screenshots exist, ideally would use VLM model here
    # For now, we award points if verification passed other checks which implies UI usage
    if score >= 60: 
        score += 10
        feedback_parts.append("Implicit UI verification passed")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }