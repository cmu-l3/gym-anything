#!/usr/bin/env python3
"""Verifier for create_hl7_channel task."""

import json
import tempfile
import os


def verify_create_hl7_channel(traj, env_info, task_info):
    """Verify that an HL7 channel was created and deployed successfully."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_channel_name = metadata.get('channel_name', 'Patient Admission Channel')
    expected_port = metadata.get('expected_port', '6661')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_hl7_channel_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract results
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    channel_exists = result.get('channel_exists', False)
    channel_name = result.get('channel_name', '')
    channel_status = result.get('channel_status', '')
    source_type = result.get('source_type', '')
    listen_port = result.get('listen_port', '')
    dest_type = result.get('dest_type', '')

    # Scoring criteria - rebalanced so channel existence alone is not enough
    score = 0
    feedback_parts = []

    # Check if a new channel was created (20 points)
    if current_count > initial_count:
        score += 20
        feedback_parts.append(f"New channel created (count: {initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"No new channel detected (count: {initial_count} -> {current_count})")

    # Check if channel exists in database (15 points)
    if channel_exists:
        score += 15
        feedback_parts.append(f"Channel found in database: '{channel_name}'")

        # Check if channel name matches expected pattern (10 points)
        actual_lower = channel_name.lower()
        has_patient = 'patient' in actual_lower
        has_admission = 'admission' in actual_lower

        if has_patient and has_admission:
            score += 10
            feedback_parts.append("Channel name matches expected pattern")
        elif has_patient or has_admission:
            score += 5
            feedback_parts.append(f"Channel name partially matches (has {'patient' if has_patient else 'admission'})")
        else:
            feedback_parts.append("Channel name doesn't match expected pattern")
    else:
        feedback_parts.append("Channel not found in database")

    # Check source connector type (15 points)
    if source_type:
        if 'tcp' in source_type.lower() or 'listener' in source_type.lower():
            score += 15
            feedback_parts.append(f"Source connector: {source_type}")
        else:
            score += 5
            feedback_parts.append(f"Source connector type: {source_type} (expected TCP Listener)")
    else:
        feedback_parts.append("Source connector type not detected")

    # Check listening port (10 points)
    if listen_port == expected_port:
        score += 10
        feedback_parts.append(f"Listening on expected port {listen_port}")
    elif listen_port:
        score += 5
        feedback_parts.append(f"Listening on port {listen_port} (expected {expected_port})")
    else:
        feedback_parts.append("Listening port not detected")

    # Check destination connector type (10 points)
    if dest_type:
        if 'file' in dest_type.lower() or 'writer' in dest_type.lower():
            score += 10
            feedback_parts.append(f"Destination connector: {dest_type}")
        else:
            score += 5
            feedback_parts.append(f"Destination type: {dest_type} (expected File Writer)")
    else:
        feedback_parts.append("Destination connector type not detected")

    # Check if channel is deployed (20 points)
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 20
        feedback_parts.append(f"Channel status: {channel_status}")
    elif status_lower not in ['', 'unknown']:
        score += 10
        feedback_parts.append(f"Channel has status: {channel_status}")
    else:
        feedback_parts.append("Channel deployment status unknown")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
