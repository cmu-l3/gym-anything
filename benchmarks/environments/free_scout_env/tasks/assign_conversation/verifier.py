#!/usr/bin/env python3
"""Verifier for assign_conversation task."""

import json
import tempfile
import os


def verify_assign_conversation(traj, env_info, task_info):
    """Verify that a conversation was assigned to the correct agent."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_conversation_subject', 'Payment issue')
    expected_assignee = metadata.get('expected_assignee_name', 'Admin User')

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

    # Criterion 1: Conversation found (15 points)
    conv_found = result.get('conversation_found', False)
    if conv_found:
        score += 15
        feedback_parts.append("Conversation found in database")
    else:
        feedback_parts.append("Conversation NOT found in database")

    # Criterion 2: Correct conversation subject (15 points)
    actual_subject = result.get('conversation_subject', '').strip()
    if actual_subject.lower() == expected_subject.lower():
        score += 15
        feedback_parts.append(f"Correct conversation: '{actual_subject}'")
    elif expected_subject.lower() in actual_subject.lower():
        score += 8
        feedback_parts.append(f"Partial subject match: '{actual_subject}'")
    else:
        feedback_parts.append(f"Subject mismatch: expected '{expected_subject}', got '{actual_subject}'")

    # Criterion 3: Conversation is assigned (30 points)
    is_assigned = result.get('is_assigned', False)
    if is_assigned:
        score += 30
        feedback_parts.append("Conversation is assigned to an agent")
    else:
        feedback_parts.append("Conversation is NOT assigned")

    # Criterion 4: Assigned to correct agent (40 points) — no partial credit for wrong agent
    assignee_first = result.get('assignee_first_name', '').strip()
    assignee_last = result.get('assignee_last_name', '').strip()
    actual_assignee = f"{assignee_first} {assignee_last}".strip()

    if actual_assignee.lower() == expected_assignee.lower():
        score += 40
        feedback_parts.append(f"Assigned to correct agent: '{actual_assignee}'")
    elif is_assigned and actual_assignee:
        feedback_parts.append(f"Assigned to wrong agent: expected '{expected_assignee}', got '{actual_assignee}'")
    else:
        feedback_parts.append("Assignee name empty or not found")

    passed = score >= 75 and conv_found and is_assigned

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
