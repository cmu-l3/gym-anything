#!/usr/bin/env python3
"""
Verifier for enforce_message_immutability task.

Checks:
1. Message_AllowDeleting == false (30 pts)
2. Message_AllowEditing == true (10 pts)
3. Message_AllowEditing_BlockEditInMinutes == 10 (30 pts)
4. Message_KeepHistory == true (30 pts)

Total: 100 pts. Pass threshold: 100 pts (Compliance tasks require strict adherence).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_message_immutability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_deleting = metadata.get('expected_allow_deleting', False)
    expected_editing = metadata.get('expected_allow_editing', True)
    expected_block_min = metadata.get('expected_block_edit_minutes', 10)
    expected_history = metadata.get('expected_keep_history', True)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": "Failed to authenticate to verify settings"}

    score = 0
    feedback = []

    # Check 1: Allow Deleting (Should be False)
    actual_deleting = result.get("allow_deleting")
    if actual_deleting == expected_deleting:
        score += 30
        feedback.append("Deletion disabled correctly.")
    else:
        feedback.append(f"Deletion setting incorrect (Expected {expected_deleting}, got {actual_deleting}).")

    # Check 2: Allow Editing (Should be True)
    actual_editing = result.get("allow_editing")
    if actual_editing == expected_editing:
        score += 10
        feedback.append("Editing enabled correctly.")
    else:
        feedback.append(f"Editing setting incorrect (Expected {expected_editing}, got {actual_editing}).")

    # Check 3: Block Edit Minutes (Should be 10)
    actual_block_min = result.get("block_edit_minutes")
    if actual_block_min == expected_block_min:
        score += 30
        feedback.append(f"Edit block window set to {expected_block_min}m correctly.")
    else:
        feedback.append(f"Edit block window incorrect (Expected {expected_block_min}, got {actual_block_min}).")

    # Check 4: Keep History (Should be True)
    actual_history = result.get("keep_history")
    if actual_history == expected_history:
        score += 30
        feedback.append("Message history enabled correctly.")
    else:
        feedback.append(f"Message history setting incorrect (Expected {expected_history}, got {actual_history}).")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }