#!/usr/bin/env python3
"""Verifier for create_saved_reply task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_saved_reply(traj, env_info, task_info):
    """
    Verify that a saved reply was created with specific content and mailbox association.
    
    Rubric:
    - Saved Reply Exists (25 pts)
    - Correct Mailbox (20 pts)
    - Content Verification (10-15 pts each for key sections)
    - Timestamp validation (10 pts)
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
    reply_found = result.get('reply_found_exact', False)
    reply_name = result.get('reply_name', '')
    reply_text = result.get('reply_text', '').lower() # lowercase for easier matching
    reply_mailbox_id = str(result.get('reply_mailbox_id', ''))
    expected_mailbox_id = str(result.get('expected_mailbox_id', ''))
    
    task_start = result.get('task_start_timestamp', 0)
    reply_created = result.get('reply_created_timestamp', 0)
    
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))

    # 1. Check if Saved Reply Exists (25 pts)
    if reply_found:
        score += 25
        feedback_parts.append(f"Saved reply '{reply_name}' created")
    elif reply_name:
        # Partial match found by export script
        score += 10
        feedback_parts.append(f"Saved reply created with incorrect name: '{reply_name}'")
    else:
        feedback_parts.append("No saved reply found with expected name")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Check Mailbox Association (20 pts)
    if reply_mailbox_id == expected_mailbox_id and expected_mailbox_id:
        score += 20
        feedback_parts.append("Correct mailbox association")
    else:
        feedback_parts.append(f"Wrong mailbox ID: got {reply_mailbox_id}, expected {expected_mailbox_id}")

    # 3. Content Verification (45 pts total)
    # Define key phrases to look for
    phrases = [
        ("password.company.com", 10),
        ("forgot password", 5),
        ("employee id", 5),
        ("verification code", 5),
        ("minimum 12 characters", 10), # or just '12 characters'
        ("extension 4357", 10)
    ]
    
    content_score = 0
    missing_phrases = []
    
    for phrase, points in phrases:
        if phrase in reply_text:
            content_score += points
        else:
            # Flexible check for "12 characters"
            if phrase == "minimum 12 characters" and ("12 characters" in reply_text or "12 chars" in reply_text):
                 content_score += points
            else:
                 missing_phrases.append(phrase)

    score += content_score
    if missing_phrases:
        feedback_parts.append(f"Content missing phrases: {', '.join(missing_phrases[:3])}...")
    else:
        feedback_parts.append("Content verified successfully")

    # 4. Anti-Gaming / Timestamp (10 pts)
    # Check if created after task start
    if reply_created >= task_start:
        score += 10
        feedback_parts.append("Created during task session")
    else:
        feedback_parts.append("WARN: Saved reply creation time predates task start")

    # 5. Check Count Increase (Safety check)
    if current_count <= initial_count:
        feedback_parts.append("WARN: Total saved reply count did not increase")
        # We don't deduct points if we found the specific reply, but it's suspicious
    
    passed = score >= 65 and reply_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }