#!/usr/bin/env python3
"""Verifier for bulk_assign_conversations task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_assign_conversations(traj, env_info, task_info):
    """
    Verify that 5 specific conversations were assigned to Marcus Chen.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('assignee_email', 'm.chen@helpdesk.local')
    
    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            conversations = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not isinstance(conversations, list) or len(conversations) == 0:
        return {"passed": False, "score": 0, "feedback": "No conversation data returned"}

    score = 0
    feedback_parts = []
    
    total_convs = len(conversations)
    assigned_count = 0
    correct_assignee_count = 0
    active_count = 0
    
    for conv in conversations:
        cid = conv.get('id')
        user_id = conv.get('user_id')
        assignee_email = conv.get('assignee_email', '').strip()
        status = str(conv.get('status')) # 1 is Active
        was_updated = conv.get('was_updated', False)
        
        item_feedback = []
        
        # Check assignment
        if user_id and user_id != 'NULL' and user_id != '':
            assigned_count += 1
            if assignee_email.lower() == expected_email.lower():
                correct_assignee_count += 1
                score += 15 # 15 pts per correct assignment
            else:
                item_feedback.append(f"Wrong assignee ({assignee_email})")
        else:
            item_feedback.append("Not assigned")
            
        # Check status (should remain Active=1)
        if status == '1':
            active_count += 1
            score += 3 # 3 pts per active ticket preservation (15 total)
        else:
            item_feedback.append(f"Status changed to {status}")
            
        # Check timestamp
        if was_updated and assignee_email.lower() == expected_email.lower():
            score += 2 # 2 pts per valid update timestamp (10 total)
            
        if item_feedback:
            feedback_parts.append(f"ID {cid}: " + ", ".join(item_feedback))

    # Summary
    if correct_assignee_count == total_convs:
        feedback_parts.append("All conversations correctly assigned.")
    else:
        feedback_parts.append(f"Correctly assigned: {correct_assignee_count}/{total_convs}.")
        
    if active_count == total_convs:
        feedback_parts.append("All conversations remained active.")
    
    # Total possible: (15+3+2) * 5 = 100
    
    passed = score >= 60 and correct_assignee_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }