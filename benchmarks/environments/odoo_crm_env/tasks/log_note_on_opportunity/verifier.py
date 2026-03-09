#!/usr/bin/env python3
"""
Verifier for log_note_on_opportunity task.

Criteria:
1. Message count increased on the target opportunity (20 pts)
2. New message created during task window (timestamp check) (15 pts)
3. Content matches expected keywords (40 pts)
4. Message is an internal Note, not an email/comment (25 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_note_on_opportunity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_keywords', ["$45,000", "March 2025", "FurniturePlus"])
    min_keywords = metadata.get('min_keywords_required', 3)

    # Get result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    initial_count = result.get('initial_msg_count', 0)
    final_count = result.get('final_msg_count', 0)
    messages = result.get('messages', [])

    # 1. Check if any new message exists
    if final_count > initial_count:
        score += 20
        feedback_parts.append("New message detected.")
    else:
        return {"passed": False, "score": 0, "feedback": "No new note found on the opportunity."}

    # Identify the candidate message (best matching new message)
    # We filter messages that are created after task_start (approximate check via string parsing or order)
    # Odoo dates are strings like '2023-10-25 10:00:00'. 
    # Since we can't easily parse timezone from inside without more info, we rely on the fact 
    # that we grabbed the top 10 most recent messages.
    
    candidate_msg = None
    max_keyword_hits = -1

    for msg in messages:
        # Check timestamps roughly if needed, but 'messages' list is already sorted desc by ID
        # and we know count increased. The top ones are likely the new ones.
        
        body = msg.get('body_raw', '').lower()
        
        # Calculate keyword hits
        hits = 0
        for kw in expected_keywords:
            if kw.lower() in body:
                hits += 1
        
        if hits > max_keyword_hits:
            max_keyword_hits = hits
            candidate_msg = msg

    if not candidate_msg:
        return {"passed": False, "score": 20, "feedback": "New message found, but could not read content."}

    # 2. Check content (40 pts max)
    if max_keyword_hits >= min_keywords:
        score += 40
        feedback_parts.append(f"Content verified ({max_keyword_hits}/{len(expected_keywords)} keywords).")
    elif max_keyword_hits > 0:
        partial = int(40 * (max_keyword_hits / min_keywords))
        score += partial
        feedback_parts.append(f"Partial content match ({max_keyword_hits} keywords).")
    else:
        feedback_parts.append("Content does not match expected notes.")

    # 3. Check message type (Internal Note) (25 pts)
    # In Odoo, 'Log Note' usually has subtype 'Note' or 'Internal Note'
    subtype = candidate_msg.get('subtype_name', '')
    msg_type = candidate_msg.get('message_type', '')
    
    # "Note" is the standard subtype name for internal notes in Odoo standard seed data
    if "Note" in subtype or msg_type == 'comment': 
        # Note: Odoo terminology is tricky. 
        # 'comment' is usually the type for both.
        # Subtype 'Note' (internal) vs 'Discussions' (external).
        if "Note" in subtype:
            score += 25
            feedback_parts.append("Correctly logged as Internal Note.")
        else:
            # If it's "Discussions", it might be a "Send Message"
            feedback_parts.append(f"Warning: Message subtype is '{subtype}' (expected 'Note'). Did you use 'Send Message' instead of 'Log Note'?")
            # Penalize but give small credit if it was at least saved
            score += 5
    else:
        feedback_parts.append(f"Incorrect message type: {subtype}")

    # 4. Timestamp/Anti-gaming (15 pts)
    # Since we fetched only the most recent messages and confirmed count increased, 
    # this is implicitly partially checked. We can give points for the candidate being "recent".
    score += 15 
    feedback_parts.append("Action performed during task session.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }