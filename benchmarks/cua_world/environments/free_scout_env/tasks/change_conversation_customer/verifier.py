#!/usr/bin/env python3
"""
Verifier for change_conversation_customer task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_customer(traj, env_info, task_info):
    """
    Verify that the conversation's customer was changed to James Whitfield.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    conv_exists = result.get('conversation_exists', False)
    initial_cid = str(result.get('initial_customer_id', ''))
    correct_cid = str(result.get('correct_customer_id', ''))
    current_cid = str(result.get('current_customer_id', ''))
    current_email = result.get('current_customer_email', '').strip()
    integrity = result.get('integrity_maintained', False)
    task_start = int(result.get('task_start_time', 0))
    last_updated = int(result.get('last_updated_time', 0))

    if not conv_exists:
        return {"passed": False, "score": 0, "feedback": "Conversation was deleted or lost"}

    # Criterion 1: Customer ID changed from initial (30 points)
    # Anti-gaming: Ensure the agent actually did something
    if current_cid != initial_cid:
        score += 30
        feedback_parts.append("Customer changed")
    else:
        feedback_parts.append("Customer ID unchanged")

    # Criterion 2: Correct customer assigned (30 points)
    if current_cid == correct_cid:
        score += 30
        feedback_parts.append("Correct customer (James Whitfield) assigned")
    else:
        feedback_parts.append(f"Wrong customer ID: expected {correct_cid}, got {current_cid}")

    # Criterion 3: Customer email updated (15 points)
    # FreeScout usually updates this automatically when customer changes
    expected_email = "james.whitfield@securecampus.com"
    if current_email.lower() == expected_email.lower():
        score += 15
        feedback_parts.append("Customer email matches")
    elif current_cid == correct_cid:
        # Partial credit if ID is right but email field didn't sync yet (unlikely but possible)
        score += 8
        feedback_parts.append("Customer ID correct, but email field not updated")
    else:
        feedback_parts.append(f"Email mismatch: {current_email}")

    # Criterion 4: Conversation Integrity (15 points)
    # Ensure they didn't just delete and recreate the conversation
    if integrity:
        score += 15
        feedback_parts.append("Conversation integrity maintained")
    else:
        feedback_parts.append("Conversation details modified or recreated")

    # Criterion 5: Updated after start (10 points)
    # Anti-gaming timestamp check
    if last_updated > task_start:
        score += 10
        feedback_parts.append("Modified during task session")
    else:
        feedback_parts.append("No modification timestamp detected during task")

    passed = (score >= 75) and (current_cid == correct_cid)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }