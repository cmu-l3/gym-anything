#!/usr/bin/env python3
"""
Verifier for reply_to_conversation task.

Scoring Criteria:
1. Reply Thread Exists (25 pts): A new reply thread was created in the conversation.
2. Reply in Correct Conversation (15 pts): The reply is in the target conversation.
3. Reply Contains Key Content (30 pts): 'restart your network adapter', 'vpn2.acmecorp.com', 'Clear Cache'.
4. Conversation Status Pending (25 pts): Status changed to 2 (Pending).
5. Reply Created by User (5 pts): The thread was created by a user, not system.

Pass Threshold: 65 points AND reply exists AND correct conversation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reply_to_conversation(traj, env_info, task_info):
    """Verify that the agent replied to the customer conversation correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_phrases', [
        "restart your network adapter", 
        "vpn2.acmecorp.com", 
        "Clear Cache"
    ])
    
    # FreeScout status codes: 1=Active, 2=Pending, 3=Closed
    expected_status = metadata.get('expected_status_id', 2)

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
    
    # 1. Reply Thread Exists (25 pts)
    reply_exists = result.get('reply_exists', False)
    if reply_exists:
        score += 25
        feedback_parts.append("New reply thread found")
    else:
        feedback_parts.append("No reply thread found created during task")

    # 2. Correct Conversation (15 pts)
    # We verify this by checking if the reply body found corresponds to the conversation
    # The export script specifically queried the target conversation ID
    target_id = result.get('target_conversation_id')
    subject = result.get('conversation_subject', '')
    
    # If we found a reply in the query that filtered by target_id, it is implicitly in the right conversation
    if reply_exists and target_id and target_id != "0":
        score += 15
        feedback_parts.append(f"Reply in correct conversation ('{subject}')")
    else:
        feedback_parts.append("Reply not associated with target conversation")

    # 3. Content Verification (30 pts, 10 per phrase)
    reply_body = result.get('reply_body', '')
    content_score = 0
    missed_phrases = []
    
    if reply_exists:
        for phrase in required_phrases:
            # Case insensitive check
            if phrase.lower() in reply_body.lower():
                content_score += 10
            else:
                missed_phrases.append(phrase)
        
        score += content_score
        if content_score == 30:
            feedback_parts.append("All content requirements met")
        elif content_score > 0:
            feedback_parts.append(f"Partial content match (Missing: {', '.join(missed_phrases)})")
        else:
            feedback_parts.append("Reply missing all required troubleshooting steps")
    else:
        feedback_parts.append("No content to verify")

    # 4. Conversation Status (25 pts)
    current_status = int(result.get('current_status', 0))
    initial_status = int(result.get('initial_status', 1))
    
    if current_status == expected_status:
        score += 25
        feedback_parts.append("Status correctly set to Pending")
    elif current_status != initial_status and current_status != 1:
        # Partial credit if they changed it but maybe to Closed?
        score += 5
        feedback_parts.append(f"Status changed to {current_status} (expected Pending)")
    else:
        feedback_parts.append("Status remained Active/Unchanged")

    # 5. User Attribution (5 pts)
    reply_user_id = result.get('reply_user_id')
    if reply_exists and reply_user_id and reply_user_id != "NULL" and reply_user_id != "0":
        score += 5
        feedback_parts.append("Reply attributed to agent")
    elif reply_exists:
        feedback_parts.append("Reply attribution unclear")

    # Final check
    # Must have at least created the reply to pass
    passed = (score >= 65) and reply_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }