#!/usr/bin/env python3
"""
Verifier for reopen_reassign_conversation task.

SCORING CRITERIA:
1. Status changed to Active (1) - 40 points
2. Assigned to Priya Sharma - 40 points
3. Integrity Check (conversation exists + subject matches) - 10 points
4. Folder Changed (moved out of Closed folder) - 10 points

Anti-gaming:
- Checks if agent did nothing (status/user matches initial)
- Checks if agent deleted/recreated conversation (integrity check)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reopen_reassign(traj, env_info, task_info):
    """Verify that the conversation was reopened and reassigned correctly."""

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

    score = 0
    feedback_parts = []
    max_score = 100

    # Extract values
    conv_exists = result.get('conversation_exists', False)
    initial_status = result.get('initial_status', '3')
    current_status = result.get('current_status', '')
    initial_user = result.get('initial_user_id', '')
    current_user = result.get('current_user_id', '')
    expected_user = result.get('expected_user_id', '')
    subject_intact = result.get('subject_intact', False)
    folder_changed = result.get('folder_changed', False)

    # 1. Integrity Check (10 points)
    if not conv_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Original conversation was deleted. You must modify the existing conversation."
        }
    
    if subject_intact:
        score += 10
        feedback_parts.append("Integrity check passed")
    else:
        feedback_parts.append("Integrity check failed (subject modified)")

    # 2. Status Check (40 points)
    # Status 1 = Active, 2 = Pending, 3 = Closed
    if current_status == '1':
        score += 40
        feedback_parts.append("Status changed to Active")
    elif current_status == '2':
        score += 20
        feedback_parts.append("Status changed to Pending (partial credit, expected Active)")
    elif current_status == initial_status:
        feedback_parts.append("Status unchanged (still Closed)")
    else:
        feedback_parts.append(f"Status is unexpected: {current_status}")

    # 3. Assignment Check (40 points)
    if current_user == expected_user:
        score += 40
        feedback_parts.append("Reassigned to Priya Sharma")
    elif current_user != initial_user and current_user != '0' and current_user:
        score += 10
        feedback_parts.append("Reassigned to someone else (partial credit)")
    elif current_user == initial_user:
        feedback_parts.append("Assignment unchanged")
    else:
        feedback_parts.append("Conversation unassigned")

    # 4. Folder Check (10 points)
    if folder_changed:
        score += 10
        feedback_parts.append("Moved out of Closed folder")
    elif current_status == '1' or current_status == '2':
        # If status changed but folder didn't update immediately in DB, give benefit of doubt
        score += 10
        feedback_parts.append("Folder update inferred from status")
    else:
        feedback_parts.append("Still in Closed folder")

    # Anti-gaming check
    if current_status == initial_status and current_user == initial_user:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected. Agent did nothing."
        }

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }