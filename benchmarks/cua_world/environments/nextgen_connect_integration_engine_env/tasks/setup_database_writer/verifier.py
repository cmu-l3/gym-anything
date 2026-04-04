#!/usr/bin/env python3
"""Verifier for setup_database_writer task."""

import json
import tempfile
import os


def verify_setup_database_writer(traj, env_info, task_info):
    """Verify that a database writer channel was created and configured."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_channel_name = metadata.get('channel_name', 'Patient DB Writer')
    expected_port = metadata.get('listen_port', '6663')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/setup_database_writer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    db_channel_exists = result.get('db_channel_exists', False)
    channel_name = result.get('channel_name', '')
    has_db_writer = result.get('has_db_writer', False)
    channel_status = result.get('channel_status', '')
    table_exists = result.get('table_exists', False)
    record_count = result.get('record_count', 0)
    listen_port = result.get('listen_port', '')

    score = 0
    feedback_parts = []

    # New channel created (10 points)
    if current_count > initial_count:
        score += 10
        feedback_parts.append(f"New channel created (count: {initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"No new channel detected (count: {initial_count} -> {current_count})")

    # Channel exists with appropriate name (15 points)
    if db_channel_exists:
        score += 15
        feedback_parts.append(f"DB writer channel found: '{channel_name}'")

        name_lower = channel_name.lower()
        has_db = 'db' in name_lower or 'database' in name_lower
        has_patient = 'patient' in name_lower
        has_writer = 'writer' in name_lower
        if has_db and has_patient:
            score += 5
            feedback_parts.append("Channel name matches expected pattern")
        elif has_db or has_patient or has_writer:
            score += 3
            feedback_parts.append("Channel name partially matches")
    else:
        feedback_parts.append("DB writer channel not found in database")

    # Database writer destination detected (25 points - primary criterion)
    if has_db_writer:
        score += 25
        feedback_parts.append("Database writer destination detected in channel config")
    else:
        feedback_parts.append("Database writer destination not detected")

    # patient_records table created (20 points)
    if table_exists:
        score += 20
        feedback_parts.append("patient_records table created in database")

        # Records inserted (10 points)
        if record_count > 0:
            score += 10
            feedback_parts.append(f"patient_records has {record_count} record(s)")
    else:
        feedback_parts.append("patient_records table not found")

    # Channel deployed (15 points)
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 15
        feedback_parts.append(f"Channel status: {channel_status}")
    elif status_lower not in ['', 'unknown']:
        score += 8
        feedback_parts.append(f"Channel has status: {channel_status}")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
