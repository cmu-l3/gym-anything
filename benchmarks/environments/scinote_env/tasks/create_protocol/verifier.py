#!/usr/bin/env python3
"""Verifier for create_protocol task."""

import json
import tempfile
import os


def verify_create_protocol(traj, env_info, task_info):
    """Verify that a new protocol was created in the protocol repository."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_protocol_name', 'Western Blot Analysis v2')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_protocol_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    criteria_passed = 0
    total_criteria = 3
    feedback_parts = []

    initial_count = int(result.get('initial_protocol_count', 0))
    current_count = int(result.get('current_protocol_count', 0))
    protocol_found = result.get('protocol_found', False)
    protocol = result.get('protocol', {})

    # Criterion 1: Protocol with expected name exists
    if protocol_found:
        actual_name = protocol.get('name', '')
        if actual_name.strip().lower() == expected_name.strip().lower():
            criteria_passed += 1
            feedback_parts.append(f"Protocol '{expected_name}' found")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Protocol '{expected_name}' not found")

    # Criterion 2: Protocol count increased
    if current_count > initial_count:
        criteria_passed += 1
        feedback_parts.append(f"Protocol count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Protocol count unchanged ({initial_count} -> {current_count})")

    # Criterion 3: Valid protocol ID
    protocol_id = protocol.get('id', '')
    if protocol_id and protocol_id.strip():
        criteria_passed += 1
        feedback_parts.append(f"Valid protocol ID: {protocol_id}")
    else:
        partial = result.get('partial_match', '')
        if partial:
            feedback_parts.append(f"Partial match found: {partial}")
        else:
            feedback_parts.append("No valid protocol ID")

    score = int((criteria_passed / total_criteria) * 100)
    passed = score >= 67  # Pass if >= 2/3 criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "name_match": protocol_found and protocol.get('name', '').strip().lower() == expected_name.strip().lower(),
            "count_increased": current_count > initial_count,
            "valid_id": bool(protocol_id and protocol_id.strip())
        }
    }
