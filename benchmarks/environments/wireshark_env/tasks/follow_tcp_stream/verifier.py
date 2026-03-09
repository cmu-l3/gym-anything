#!/usr/bin/env python3
"""Verifier for follow_tcp_stream task."""

import json
import tempfile
import os


def verify_follow_tcp_stream(traj, env_info, task_info):
    """Verify that the user followed a TCP stream and saved the SMTP conversation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    feedback_parts = []
    score = 0

    # Criterion 1: Output file exists (20 pts)
    if result.get('output_file_exists'):
        score += 20
        feedback_parts.append("Stream output file created")
    else:
        feedback_parts.append("Stream output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File has meaningful content (15 pts)
    content_length = result.get('content_length', 0)
    if content_length > 100:
        score += 15
        feedback_parts.append(f"File has substantial content ({content_length} chars)")
    elif content_length > 0:
        score += 5
        feedback_parts.append(f"File has minimal content ({content_length} chars)")
    else:
        feedback_parts.append("File is empty")

    # Criterion 3: Contains EHLO/HELO greeting (15 pts)
    if result.get('has_ehlo'):
        score += 15
        feedback_parts.append("Contains SMTP greeting (EHLO/HELO)")
    else:
        feedback_parts.append("Missing SMTP greeting")

    # Criterion 4: Contains MAIL FROM command (15 pts)
    if result.get('has_mail_from'):
        score += 15
        feedback_parts.append("Contains MAIL FROM command")
    else:
        feedback_parts.append("Missing MAIL FROM command")

    # Criterion 5: Contains RCPT TO command (15 pts)
    if result.get('has_rcpt_to'):
        score += 15
        feedback_parts.append("Contains RCPT TO command")
    else:
        feedback_parts.append("Missing RCPT TO command")

    # Criterion 6: Contains SMTP response codes (20 pts)
    if result.get('has_smtp_response_codes'):
        score += 20
        feedback_parts.append("Contains SMTP server response codes")
    elif result.get('has_data_command'):
        score += 10
        feedback_parts.append("Contains DATA command but missing response codes")
    else:
        feedback_parts.append("Missing SMTP response codes")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
