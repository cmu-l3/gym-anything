#!/usr/bin/env python3
"""Verifier for configure_channel_filter task."""

import json
import tempfile
import os


def verify_configure_channel_filter(traj, env_info, task_info):
    """Verify that a channel with message filtering was created."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_channel_name = metadata.get('channel_name', 'ADT Filter Channel')
    expected_port = metadata.get('listen_port', '6662')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_channel_filter_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    filter_channel_exists = result.get('filter_channel_exists', False)
    channel_name = result.get('channel_name', '')
    has_filter = result.get('has_filter', False)
    channel_status = result.get('channel_status', '')
    listen_port = result.get('listen_port', '')

    score = 0
    feedback_parts = []

    # New channel created (15 points)
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"New channel created (count: {initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"No new channel detected (count: {initial_count} -> {current_count})")

    # Channel exists with appropriate name (15 points)
    if filter_channel_exists:
        score += 15
        feedback_parts.append(f"Filter channel found: '{channel_name}'")

        name_lower = channel_name.lower()
        has_filter_word = 'filter' in name_lower
        has_adt_word = 'adt' in name_lower
        if has_filter_word and has_adt_word:
            score += 10
            feedback_parts.append("Channel name matches expected pattern (filter + ADT)")
        elif has_filter_word or has_adt_word:
            score += 5
            feedback_parts.append(f"Channel name partially matches (has {'filter' if has_filter_word else 'adt'})")
    else:
        feedback_parts.append("Filter channel not found in database")

    # Filter logic detected (30 points - primary criterion)
    if has_filter:
        score += 30
        feedback_parts.append("Filter logic detected in channel configuration")
    else:
        feedback_parts.append("Filter logic not detected in channel XML")

    # Listen port correct (10 points)
    if listen_port == expected_port:
        score += 10
        feedback_parts.append(f"Listening on expected port {listen_port}")
    elif listen_port:
        score += 5
        feedback_parts.append(f"Listening on port {listen_port} (expected {expected_port})")

    # Channel deployed (20 points)
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 20
        feedback_parts.append(f"Channel status: {channel_status}")
    elif status_lower not in ['', 'unknown']:
        score += 10
        feedback_parts.append(f"Channel has status: {channel_status}")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
