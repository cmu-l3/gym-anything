#!/usr/bin/env python3
"""Verifier for merge_duplicate_tickets task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_tickets(traj, env_info, task_info):
    """
    Verify that duplicate tickets were merged.
    
    Criteria:
    1. Exactly one active conversation remains for the customer (40 pts).
    2. The surviving conversation contains the body text of ticket 1 (20 pts).
    3. The surviving conversation contains the body text of ticket 2 (20 pts).
    4. The surviving conversation contains the body text of ticket 3 (20 pts).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # Criterion 1: Single Active Conversation (40 pts)
    active_count = result.get('active_conversation_count', -1)
    
    if active_count == 1:
        score += 40
        feedback_parts.append("Correct: Only 1 active conversation remains")
    elif active_count == 0:
        feedback_parts.append("Fail: No active conversations found (tickets deleted/closed instead of merged?)")
    elif active_count > 1:
        feedback_parts.append(f"Fail: {active_count} active conversations remaining (merging incomplete)")
    else:
        feedback_parts.append("Fail: Could not determine conversation count")

    # Criteria 2-4: Content Preservation (20 pts each)
    # This verifies that they were actually MERGED, not just deleted/closed.
    # If they were just closed, the active count check might fail (if closed=inactive),
    # or if they deleted 2 and kept 1, the text check will fail for the deleted ones.
    
    found_1 = result.get('found_text_1', False)
    found_2 = result.get('found_text_2', False)
    found_3 = result.get('found_text_3', False)
    
    survivor_valid = (active_count == 1)
    
    if found_1:
        score += 20
        feedback_parts.append("Content of Ticket 1 preserved")
    else:
        feedback_parts.append("Content of Ticket 1 missing")
        
    if found_2:
        score += 20
        feedback_parts.append("Content of Ticket 2 preserved")
    else:
        feedback_parts.append("Content of Ticket 2 missing")
        
    if found_3:
        score += 20
        feedback_parts.append("Content of Ticket 3 preserved")
    else:
        feedback_parts.append("Content of Ticket 3 missing")

    # Pass threshold: 100 points required.
    # Merging is a binary outcome effectively: either it's clean and complete, or it's messy.
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }