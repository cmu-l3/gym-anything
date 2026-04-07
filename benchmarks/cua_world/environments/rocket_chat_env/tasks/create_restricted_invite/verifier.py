#!/usr/bin/env python3
"""
Verifier for create_restricted_invite task.

Verification Strategy:
1. Parse exported JSON from REST API to check if target message exists in the channel.
2. Verify the message contains the expected string and is pinned.
3. Parse dumped MongoDB invites to verify a workspace invite was created.
4. Validate invite parameters: exactly 7 days expiration and 50 max uses.
5. Cross-reference the token in the message with the actual generated invite record.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_restricted_invite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Get target text from metadata
    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', 'Official Beta Program Invite Link')
    expected_days = metadata.get('expected_days', 7)
    expected_uses = metadata.get('expected_max_uses', 50)

    # Read the exported files
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_inv = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)

        copy_from_env("/tmp/mongo_invites.json", temp_inv.name)
        try:
            with open(temp_inv.name, 'r') as f:
                invites = json.load(f)
        except json.JSONDecodeError:
            invites = []
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result files: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
        if os.path.exists(temp_inv.name):
            os.unlink(temp_inv.name)

    messages = result.get("messages", [])

    # 1. Find the message containing the target text
    target_msg = None
    for msg in messages:
        if expected_text in msg.get("msg", ""):
            target_msg = msg
            break

    if target_msg:
        score += 10
        feedback.append("Target message found in channel.")

        # 2. Check if the message is pinned
        if target_msg.get("pinned", False):
            score += 20
            feedback.append("Message is successfully pinned.")
        else:
            feedback.append("Message is NOT pinned.")
    else:
        feedback.append(f"Target message containing '{expected_text}' NOT found in channel.")

    # 3. Find the created workspace invite
    target_invite = None
    
    # Try to correlate via the message's text (token should be in the URL)
    if target_msg:
        msg_text = target_msg.get("msg", "")
        for inv in invites:
            token = inv.get("_id", "")
            if token and token in msg_text:
                target_invite = inv
                break

    # Fallback: Just grab the most recent invite if it wasn't matched
    if not target_invite and len(invites) > 0:
        target_invite = invites[-1]

    if target_invite:
        score += 20
        feedback.append("New workspace invite found in database.")

        # 4. Check properties (days and maxUses)
        days = target_invite.get("days")
        max_uses = target_invite.get("maxUses")

        # Safely parse numeric properties
        try:
            days = int(days) if days is not None else 0
        except ValueError:
            days = 0

        try:
            max_uses = int(max_uses) if max_uses is not None else 0
        except ValueError:
            max_uses = 0

        if days == expected_days:
            score += 20
            feedback.append(f"Invite expiration correctly set to {expected_days} days.")
        else:
            feedback.append(f"Invite expiration incorrect (expected {expected_days}, found {days}).")

        if max_uses == expected_uses:
            score += 20
            feedback.append(f"Invite max uses correctly set to {expected_uses}.")
        else:
            feedback.append(f"Invite max uses incorrect (expected {expected_uses}, found {max_uses}).")

        # 5. Check if the message contains the exact invite token
        if target_msg and target_invite.get("_id") in target_msg.get("msg", ""):
            score += 10
            feedback.append("Message contains the correct invite token.")
        else:
            feedback.append("Message does not appear to contain the correct generated invite URL/token.")
    else:
        feedback.append("No workspace invites found in database.")

    # Determine overall passing criteria
    # To pass, the agent must have created the invite correctly AND posted it.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }