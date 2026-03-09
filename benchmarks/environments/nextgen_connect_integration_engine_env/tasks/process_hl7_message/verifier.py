#!/usr/bin/env python3
"""Verifier for process_hl7_message task."""

import json
import tempfile
import os


def verify_process_hl7_message(traj, env_info, task_info):
    """Verify that an HL7 message was successfully processed through a channel."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/process_hl7_message_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract results
    channel_count = result.get('channel_count', 0)
    message_processed = result.get('message_processed', 'false')
    new_messages = result.get('new_messages', 0)
    received_count = result.get('received_count', 0)
    evidence_found = result.get('evidence_found', '')

    # Scoring criteria
    score = 0
    feedback_parts = []

    # Check if channel exists (required prerequisite - 10 points)
    if channel_count > 0:
        score += 10
        feedback_parts.append(f"Channel(s) exist for message processing (count: {channel_count})")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channels exist. A channel must be created first."
        }

    # Check if NEW messages were processed via delta (primary criterion - 50 points)
    if new_messages > 0:
        score += 50
        feedback_parts.append(f"New message(s) processed: {new_messages} (delta from initial)")
    elif message_processed == "true":
        # Fallback: messages exist but can't confirm they're new
        score += 30
        feedback_parts.append("Message processing detected but cannot confirm new messages")
    else:
        feedback_parts.append("No new message processing detected")

    # Check received count via API (20 points)
    if received_count > 0:
        score += 20
        feedback_parts.append(f"API statistics show {received_count} total received message(s)")

    # Check evidence types (20 points max)
    if evidence_found:
        evidence_types = evidence_found.split(',')
        evidence_score = 0

        if 'api_statistics' in evidence_types:
            evidence_score += 8

        if 'message_tables' in evidence_types:
            evidence_score += 7
            feedback_parts.append("Message data found in database tables")

        if 'output_files' in evidence_types:
            evidence_score += 7
            feedback_parts.append("Output files created by channel")

        score += min(evidence_score, 20)

    passed = score >= 60
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
