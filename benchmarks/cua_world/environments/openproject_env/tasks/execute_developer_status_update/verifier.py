#!/usr/bin/env python3
"""
Verifier for execute_developer_status_update task.

Verifies:
1. Work package status update (10 pts)
2. Progress % update (10 pts)
3. Time logging - correct amount and USER attribution (30 pts)
4. Commenting - correct text and USER attribution (30 pts)
5. User login verification (20 pts - implicitly checked via attribution)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_developer_status_update(traj, env_info, task_info):
    """
    Verify that Alice Johnson updated her work package correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_status = metadata.get('expected_status', 'In progress')
    expected_percent = metadata.get('expected_percent', 20)
    expected_hours = metadata.get('expected_hours', 4.0)
    expected_comment_fragment = metadata.get('expected_comment_fragment', 'Initial indexing structure created')
    target_user = metadata.get('target_user_login', 'alice.johnson')

    # Copy result file
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

    # Check for script errors
    if result.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification script error: {result['error']}"
        }

    if not result.get('wp_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target work package 'Implement product search...' not found."
        }

    score = 0
    feedback = []

    # 1. Verify Status (10 pts)
    actual_status = result.get('status', '')
    if actual_status.lower() == expected_status.lower():
        score += 10
        feedback.append(f"Status updated to '{actual_status}' (10/10)")
    else:
        feedback.append(f"Status mismatch: expected '{expected_status}', got '{actual_status}'")

    # 2. Verify Progress (10 pts)
    actual_ratio = result.get('done_ratio', 0)
    if actual_ratio == expected_percent:
        score += 10
        feedback.append(f"Progress updated to {actual_ratio}% (10/10)")
    else:
        feedback.append(f"Progress mismatch: expected {expected_percent}%, got {actual_ratio}%")

    # 3. Verify Time Logging & Attribution (30 pts)
    # Attribution is key here - did ALICE log it?
    hours_logged = result.get('hours_logged', 0.0)
    time_user = result.get('time_entry_user', None)

    if hours_logged == expected_hours:
        if time_user == target_user:
            score += 30
            feedback.append(f"Correctly logged {hours_logged}h as {target_user} (30/30)")
        else:
            score += 10 # Partial credit for logging time but wrong user
            feedback.append(f"Logged {hours_logged}h but as wrong user '{time_user}' (expected {target_user}) (10/30)")
    elif hours_logged > 0:
        if time_user == target_user:
            score += 15 # Partial for correct user but wrong amount
            feedback.append(f"Logged {hours_logged}h as {target_user} (expected {expected_hours}h) (15/30)")
        else:
            feedback.append(f"Logged {hours_logged}h as wrong user '{time_user}' (0/30)")
    else:
        feedback.append("No time logged by Alice for this task today (0/30)")

    # 4. Verify Comment & Attribution (30 pts)
    last_comment = result.get('last_comment', '') or ""
    comment_author = result.get('comment_author', None)

    if expected_comment_fragment.lower() in last_comment.lower():
        if comment_author == target_user:
            score += 30
            feedback.append(f"Correct comment added by {target_user} (30/30)")
        else:
            score += 10 # Partial for content
            feedback.append(f"Comment content correct but author was '{comment_author}' (10/30)")
    elif last_comment:
        if comment_author == target_user:
            score += 10 # Partial for authoring a comment
            feedback.append(f"Comment added by {target_user} but text mismatch (10/30)")
        else:
            feedback.append(f"Incorrect comment by wrong user '{comment_author}' (0/30)")
    else:
        feedback.append("No comment found by Alice on this task today (0/30)")

    # 5. User Login Check (20 pts)
    # This is implicitly checked by the attribution of time/comments.
    # If they got full points on attribution, they were logged in correctly.
    # We award these points if EITHER time OR comment was attributed to Alice.
    if time_user == target_user or comment_author == target_user:
        score += 20
        feedback.append(f"Successfully performed actions as {target_user} (20/20)")
    else:
        feedback.append(f"Failed to perform actions as {target_user} - likely used Admin account (0/20)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }