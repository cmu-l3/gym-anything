#!/usr/bin/env python3
"""Verifier for add_internal_follower task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_internal_follower(traj, env_info, task_info):
    """
    Verify that Marcus Reynolds was added as a follower and Sarah Chen remains the assignee.
    """
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
    
    # Extract data
    marcus_is_follower = result.get('marcus_is_follower', False)
    assignee_is_sarah = result.get('assignee_is_sarah', False)
    assignee_is_marcus = result.get('assignee_is_marcus', False)
    ticket_is_active = result.get('ticket_is_active', False)
    conversation_id = result.get('conversation_id', "")

    # Basic validity check
    if not conversation_id:
        return {"passed": False, "score": 0, "feedback": "Target conversation not found or deleted."}

    # CRITERION 1: Marcus Added as Follower (40 pts)
    if marcus_is_follower:
        score += 40
        feedback_parts.append("PASS: Marcus Reynolds added as follower")
    else:
        feedback_parts.append("FAIL: Marcus Reynolds NOT found in followers list")

    # CRITERION 2: Sarah Remains Assignee (40 pts)
    if assignee_is_sarah:
        score += 40
        feedback_parts.append("PASS: Sarah Chen is still the assignee")
    elif assignee_is_marcus:
        # User made a common mistake: assigning instead of following
        feedback_parts.append("FAIL: You assigned the ticket to Marcus (ownership change) instead of adding him as a follower")
    else:
        feedback_parts.append("FAIL: Sarah Chen is no longer the assignee")

    # CRITERION 3: Ticket Still Active (10 pts)
    if ticket_is_active:
        score += 10
        feedback_parts.append("PASS: Ticket status is Active")
    else:
        feedback_parts.append("FAIL: Ticket status was changed (closed/spam/deleted)")

    # CRITERION 4: Action on specific ticket (10 pts)
    # Implicitly checked because export script looked up the specific ID
    if marcus_is_follower or assignee_is_sarah:
        score += 10
        feedback_parts.append("PASS: Correct conversation target")

    # Pass threshold: Must have added follower AND kept assignee correct
    passed = (score >= 80) and marcus_is_follower and assignee_is_sarah

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }