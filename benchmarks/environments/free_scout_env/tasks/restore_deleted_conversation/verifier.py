#!/usr/bin/env python3
"""
Verifier for restore_deleted_conversation task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_deleted_conversation(traj, env_info, task_info):
    """
    Verify that the conversation was restored from Deleted state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Extract data
    initial_state = result.get('initial_state', '3')
    current_state = str(result.get('current_state', '3'))
    current_status = str(result.get('current_status', '0'))
    current_mailbox = str(result.get('current_mailbox_id', ''))
    expected_mailbox = str(result.get('expected_mailbox_id', ''))
    updated_at = int(result.get('updated_at_unix', 0) or 0)
    task_start = int(result.get('task_start_time', 0) or 0)

    # 1. Verify State Change (50 points)
    # State 1 = Published/Active, State 3 = Deleted
    if current_state == '1':
        score += 50
        feedback_parts.append("Conversation restored to Published state")
    elif current_state == '2':
        score += 20
        feedback_parts.append("Conversation is in Draft state (partial credit)")
    elif current_state == '3':
        feedback_parts.append("Conversation is still in Deleted state")
    else:
        feedback_parts.append(f"Conversation state is unknown ({current_state})")

    # 2. Verify Status is valid (20 points)
    # 1=Active, 2=Pending, 3=Closed
    if current_status in ['1', '2']:
        score += 20
        feedback_parts.append("Conversation status is Active/Pending")
    elif current_status == '3':
        score += 10
        feedback_parts.append("Conversation is restored but Closed")
    else:
        feedback_parts.append(f"Conversation status unexpected ({current_status})")

    # 3. Verify Mailbox Integrity (15 points)
    if current_mailbox and current_mailbox == expected_mailbox:
        score += 15
        feedback_parts.append("Conversation remains in correct mailbox")
    else:
        feedback_parts.append(f"Conversation moved to wrong mailbox (got {current_mailbox}, expected {expected_mailbox})")

    # 4. Anti-gaming: Verify Timestamp (15 points)
    if updated_at > task_start:
        score += 15
        feedback_parts.append("Conversation modified during task")
    else:
        feedback_parts.append("No modification timestamp detected during task window")

    # Sanity check: if state is still deleted (3), score should be very low regardless of other factors
    if current_state == '3':
        score = min(score, 15) # Cap score if primary goal failed
        feedback_parts.append("FAILED: Primary goal (restore from deleted) not met")

    passed = score >= 65 and current_state == '1'

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }