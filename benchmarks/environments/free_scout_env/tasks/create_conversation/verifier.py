#!/usr/bin/env python3
"""Verifier for create_conversation task."""

import json
import tempfile
import os


def verify_create_conversation(traj, env_info, task_info):
    """Verify that a new conversation was created in FreeScout."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Peripheral compatibility')
    expected_customer_email = metadata.get('expected_customer_email', 'clarkeashley@example.com')

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

    # Criterion 1: Conversation count increased (15 points)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"Conversation count increased: {initial_count} -> {current_count}")
    else:
        feedback_parts.append(f"Conversation count unchanged: {initial_count} -> {current_count}")

    # Criterion 2: Conversation found in database (15 points)
    conv_found = result.get('conversation_found', False)
    if conv_found:
        score += 15
        feedback_parts.append("Conversation found in database")
    else:
        feedback_parts.append("Conversation NOT found in database")

    # Criterion 3: Subject matches (25 points)
    actual_subject = result.get('conversation_subject', '').strip()
    if actual_subject.lower() == expected_subject.lower():
        score += 25
        feedback_parts.append(f"Subject matches: '{actual_subject}'")
    elif expected_subject.lower() in actual_subject.lower() or actual_subject.lower() in expected_subject.lower():
        score += 12
        feedback_parts.append(f"Subject partial match: expected '{expected_subject}', got '{actual_subject}'")
    else:
        feedback_parts.append(f"Subject mismatch: expected '{expected_subject}', got '{actual_subject}'")

    # Criterion 4: Customer email matches (20 points)
    actual_email = result.get('customer_email', '').strip()
    if actual_email.lower() == expected_customer_email.lower():
        score += 20
        feedback_parts.append(f"Customer email matches: '{actual_email}'")
    elif actual_email:
        score += 5
        feedback_parts.append(f"Customer email set but mismatch: expected '{expected_customer_email}', got '{actual_email}'")
    else:
        feedback_parts.append("Customer email not set")

    # Criterion 5: Thread/message body exists (15 points)
    thread_count = int(result.get('thread_count', 0))
    if thread_count > 0:
        score += 15
        feedback_parts.append(f"Message body written ({thread_count} thread(s))")
    else:
        feedback_parts.append("No message body found")

    # Criterion 6: Conversation has a mailbox assigned (10 points)
    mailbox_id = result.get('conversation_mailbox_id', '')
    if mailbox_id and mailbox_id != '0' and mailbox_id != 'NULL':
        score += 10
        feedback_parts.append(f"Mailbox assigned (id={mailbox_id})")
    else:
        feedback_parts.append("No mailbox assigned")

    passed = score >= 70 and conv_found and current_count > initial_count

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
