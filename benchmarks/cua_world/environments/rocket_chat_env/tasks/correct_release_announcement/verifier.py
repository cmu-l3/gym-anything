#!/usr/bin/env python3
"""
Verifier for correct_release_announcement task.

Verification Strategy:
1. Ensure the original message ID still exists (agent used 'Edit' feature, didn't delete/repost) (20 points)
2. Ensure the message was actually edited (editedAt timestamp exists) (20 points)
3. Content match: the text must contain the core warning sentence (30 points)
4. Formatting check: the word WARNING must be bolded using markdown (**WARNING** or __WARNING__) (30 points)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_release_announcement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text_core = metadata.get('expected_text_core', 'Release 8.0.0 has been pulled due to a critical bug. Do not upgrade.')

    # Copy exported result JSON from the environment
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

    msg_found = result.get('message_found', False)
    msg_text = result.get('message_text', '')
    edited_at = result.get('edited_at', '')

    # Criterion 1: Message Preserved
    if msg_found:
        score += 20
        feedback_parts.append("Original message ID preserved (Edit UI used)")
    else:
        feedback_parts.append("Original message NOT found (Task failed: message deleted or never injected)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Message Edited
    if edited_at and edited_at != 'null':
        score += 20
        feedback_parts.append("Message 'editedAt' status confirmed")
    else:
        feedback_parts.append("Message was NOT edited")

    # Criterion 3: Content Match
    # Normalize spacing and check case-insensitively
    normalized_target = expected_text_core.lower().replace(" ", "")
    normalized_actual = msg_text.lower().replace(" ", "")
    
    if normalized_target in normalized_actual:
        score += 30
        feedback_parts.append("Correct warning text is present")
    else:
        feedback_parts.append(f"Warning text missing or incorrect. Found: {msg_text[:30]}...")

    # Criterion 4: Formatting Match (Markdown bold)
    if "**warning**" in msg_text.lower() or "__warning__" in msg_text.lower():
        score += 30
        feedback_parts.append("Markdown formatting applied correctly")
    else:
        feedback_parts.append("Markdown formatting (**WARNING**) is missing or malformed")

    # 70+ points required to pass (Must edit the message and get the content right)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }