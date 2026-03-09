#!/usr/bin/env python3
"""
Verifier for move_conversation_to_mailbox task.

Criteria:
1. Conversation still exists (15 pts) - ensures agent didn't delete it
2. Moved to correct mailbox (50 pts) - primary goal
3. Modification detected (15 pts) - anti-gaming check (timestamp)
4. Subject preserved (10 pts) - data integrity
5. Removed from original mailbox (10 pts) - confirms move operation
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_move_conversation(traj, env_info, task_info):
    """Verify that the conversation was moved to the correct mailbox."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', "Printer cannot connect to network after office move")

    # Load result file
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
    
    # 1. Conversation still exists (15 pts)
    still_exists = result.get("conversation_still_exists", False)
    if still_exists:
        score += 15
        feedback_parts.append("Conversation exists")
    else:
        feedback_parts.append("FAIL: Conversation was deleted or not found")
        # Critical failure
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Moved to correct mailbox (50 pts)
    moved_correctly = result.get("moved_to_correct_mailbox", False)
    current_mailbox = result.get("current_mailbox_id", "unknown")
    target_mailbox = result.get("netsupport_mailbox_id", "unknown")
    
    if moved_correctly:
        score += 50
        feedback_parts.append("Moved to target mailbox")
    else:
        feedback_parts.append(f"FAIL: Not in target mailbox (current ID: {current_mailbox}, target ID: {target_mailbox})")

    # 3. Modification detected (15 pts) - Anti-gaming
    was_modified = result.get("was_modified", False)
    if was_modified:
        score += 15
        feedback_parts.append("Modification detected")
    else:
        feedback_parts.append("FAIL: No modification detected (timestamp unchanged)")

    # 4. Subject preserved (10 pts)
    current_subject = result.get("current_subject", "").strip()
    # Simple check for the unique part of the subject
    if "Printer cannot connect" in current_subject:
        score += 10
        feedback_parts.append("Subject preserved")
    else:
        feedback_parts.append(f"FAIL: Subject changed/incorrect ('{current_subject}')")

    # 5. Removed from original mailbox (10 pts)
    removed = result.get("removed_from_original", False)
    if removed:
        score += 10
        feedback_parts.append("Removed from source mailbox")
    else:
        feedback_parts.append("FAIL: Still in source mailbox")

    # Pass threshold: 60 points
    # This requires at minimum: Exists (15) + Moved (50) = 65 points
    passed = score >= 60 and moved_correctly

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }