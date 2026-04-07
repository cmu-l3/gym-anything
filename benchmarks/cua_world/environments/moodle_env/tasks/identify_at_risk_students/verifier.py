#!/usr/bin/env python3
"""
Verifier for Identify At-Risk Students task.

Checks:
1. Messages containing "catch up" were sent after task start.
2. Inactive users (dlee, epatel) RECEIVED the message.
3. Active users (fkim, awilson, bbrown) did NOT receive the message.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_at_risk_students(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_users = set(metadata.get('target_users', ['dlee', 'epatel']))
    control_users = set(metadata.get('control_users', ['fkim', 'awilson', 'bbrown']))
    required_text = metadata.get('required_text', 'catch up').lower()

    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    messages = result.get('messages', [])
    messaged_users = set()
    correct_content_count = 0

    # Aggregate all users who received a valid message
    for msg in messages:
        content = msg.get('content', '').lower()
        if required_text in content:
            correct_content_count += 1
            recipients = msg.get('recipients', [])
            for r in recipients:
                messaged_users.add(r)

    score = 0
    feedback = []

    # Scoring Criteria
    
    # 1. Content check (10 pts)
    if correct_content_count > 0:
        score += 10
        feedback.append("Valid message content sent.")
    else:
        feedback.append(f"No message found containing '{required_text}'.")

    # 2. Target Users (Inactive) - 25 pts each (50 total)
    targets_hit = 0
    for u in target_users:
        if u in messaged_users:
            score += 25
            targets_hit += 1
            feedback.append(f"Correctly messaged inactive user: {u}")
        else:
            feedback.append(f"Missed inactive user: {u}")

    # 3. Control Users (Active) - 20 pts (Precision check)
    # Deduct or award based on NOT messaging them
    controls_hit = 0
    for u in control_users:
        if u in messaged_users:
            controls_hit += 1
            feedback.append(f"Incorrectly messaged active user: {u}")
    
    # 40 points allocated for precision (Control group)
    # If NO controls hit -> 40 points
    # If 1 hit -> 20 points
    # If 2+ hit -> 0 points
    precision_score = 0
    if controls_hit == 0:
        precision_score = 40
        feedback.append("Precision bonus: No active students messaged.")
    elif controls_hit == 1:
        precision_score = 20
        feedback.append("Precision penalty: One active student messaged.")
    else:
        feedback.append("Precision fail: Multiple active students messaged.")
    
    score += precision_score

    passed = (score >= 80) and (targets_hit == len(target_users))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "messaged_users": list(messaged_users),
            "targets_hit": targets_hit,
            "controls_hit": controls_hit
        }
    }