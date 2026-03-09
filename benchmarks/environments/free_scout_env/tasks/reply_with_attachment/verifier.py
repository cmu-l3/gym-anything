#!/usr/bin/env python3
"""Verifier for reply_with_attachment task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reply_with_attachment(traj, env_info, task_info):
    """
    Verify that the agent replied to the ticket with the correct attachment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('attachment_filename', 'VPN_Setup_Guide_v2.pdf')

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

    score = 0
    feedback_parts = []

    # 1. Check if a reply was sent (30 points)
    reply_found = result.get('reply_found', False)
    initial_count = int(result.get('initial_thread_count', 0))
    current_count = int(result.get('current_thread_count', 0))

    if reply_found and current_count > initial_count:
        score += 30
        feedback_parts.append("Reply sent successfully")
    else:
        feedback_parts.append("No new reply found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Check for attachment existence (30 points)
    attachment_found = result.get('attachment_found', False)
    if attachment_found:
        score += 30
        feedback_parts.append("Attachment found on reply")
    else:
        feedback_parts.append("Reply sent but NO attachment found")
        # Fail immediately if core requirement missing
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Check attachment filename (30 points)
    actual_filename = result.get('attachment_name', '').strip()
    if actual_filename == expected_filename:
        score += 30
        feedback_parts.append(f"Correct file attached: {actual_filename}")
    elif expected_filename in actual_filename:
        score += 15
        feedback_parts.append(f"Filename partial match: '{actual_filename}'")
    else:
        feedback_parts.append(f"Wrong file attached: expected '{expected_filename}', got '{actual_filename}'")

    # 4. Check for polite message body (10 points)
    body_preview = result.get('reply_body_preview', '').strip()
    if len(body_preview) > 5:
        score += 10
        feedback_parts.append("Message body text present")
    else:
        feedback_parts.append("Message body empty or too short")

    passed = score >= 90  # Strict pass: Must reply + attach correct file

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }