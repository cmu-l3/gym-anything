#!/usr/bin/env python3
"""Verifier for dispatch_new_incident_type task."""

import json
import tempfile
import os


def verify_dispatch_new_incident_type(traj, env_info, task_info):
    """Verify that a new incident type was added and a call was dispatched using it."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_type = metadata.get('expected_type_name', 'Rock Slide').lower()
    expected_location = metadata.get('expected_location', 'North Haul Road').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dispatch_new_incident_type_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Incident Type Created (30 pts)
    type_found = result.get('type_found', False)
    created_type = result.get('created_type', {})
    type_name = (created_type.get('name') or '').strip().lower()

    if type_found and expected_type in type_name:
        score += 30
        feedback_parts.append(f"Incident Type '{created_type.get('name')}' created")
    elif type_found:
        score += 15
        feedback_parts.append(f"Incident Type created but name mismatch: '{type_name}'")
    else:
        feedback_parts.append("No new Incident Type found")

    # Criterion 2: Call Created at Location (20 pts)
    call_found = result.get('call_found', False)
    created_call = result.get('created_call', {})
    call_location = (created_call.get('location') or '').strip().lower()

    if call_found and expected_location in call_location:
        score += 20
        feedback_parts.append(f"Call created at '{created_call.get('location')}'")
    elif call_found:
        score += 10
        feedback_parts.append(f"Call created but location mismatch: '{call_location}'")
    else:
        feedback_parts.append("No dispatch call found")

    # Criterion 3: Call Linked to New Type (30 pts)
    linked = result.get('linked_correctly', False)
    call_type_val = (created_call.get('type_value') or '').lower()

    if linked:
        score += 30
        feedback_parts.append("Call correctly linked to new Incident Type")
    elif call_found and expected_type in call_type_val:
        # Fallback if the export logic missed the link but string matches
        score += 30
        feedback_parts.append("Call linked to correct type name")
    elif call_found:
        feedback_parts.append(f"Call linked to wrong type: '{call_type_val}'")

    # Criterion 4: Anti-gaming / Effort (20 pts)
    # Check if counts increased implies work was done
    init_type_count = result.get('initial_type_count', 0)
    curr_type_count = result.get('current_type_count', 0)
    init_call_count = result.get('initial_call_count', 0)
    curr_call_count = result.get('current_call_count', 0)

    if curr_type_count > init_type_count:
        score += 10
    if curr_call_count > init_call_count:
        score += 10
    
    if score >= 90:
        feedback_parts.append("Counts verified")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }