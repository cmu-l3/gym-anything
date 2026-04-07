#!/usr/bin/env python3
"""
Verifier for email_handoff_preparation task.

Scoring Criteria (Total 100):
1. Handoff folder creation (15 pts) - Folder name contains "handoff"
2. Folder populated (20 pts) - Contains 8+ emails
3. Source diversity (15 pts) - Emails from 3+ distinct mailing lists
4. Inbox reduction (10 pts) - Inbox count reduced by 8+
5. Briefing email (20 pts) - Draft/Sent to backup@techcorp.org
6. Subject line (10 pts) - Contains keywords (handoff, transition, etc.)
7. Body content (10 pts) - Mentions 2+ specific list names
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_handoff(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    initial_inbox = int(task_info.get('metadata', {}).get('initial_inbox_count', 50)) # Fallback if not passed, but usually read from file in real run logic if needed, here we trust verifier logic or export script output. 
    # Actually, let's use the export script's result vs metadata expectations.
    
    # Read result
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
    
    handoff_data = result.get('handoff_folder', {})
    outgoing = result.get('outgoing_emails', [])
    current_inbox = result.get('inbox_count', 50)
    
    # We need the baseline inbox count to calculate reduction. 
    # Since verifier doesn't read /tmp/initial_inbox_count directly (it's in container),
    # we assume standard starting state of 50 or rely on what export script could have provided.
    # The export script provided 'inbox_count'. We know start was 50 from setup.
    START_INBOX = 50 

    # 1. Handoff Folder Created (15 pts)
    if handoff_data.get('exists'):
        score += 15
        feedback_parts.append(f"Folder '{handoff_data['name']}' created")
    else:
        feedback_parts.append("No 'handoff' folder found")

    # 2. Folder Populated (20 pts)
    count = handoff_data.get('count', 0)
    if count >= 8:
        score += 20
        feedback_parts.append(f"Folder populated ({count} emails)")
    elif count >= 4:
        score += 10
        feedback_parts.append(f"Folder partially populated ({count}/8 emails)")
    else:
        feedback_parts.append(f"Folder insufficient ({count}/8 emails)")

    # 3. Source Diversity (15 pts)
    distinct_lists = handoff_data.get('distinct_list_count', 0)
    if distinct_lists >= 3:
        score += 15
        feedback_parts.append(f"Good diversity ({distinct_lists} lists)")
    elif distinct_lists == 2:
        score += 8
        feedback_parts.append(f"Partial diversity ({distinct_lists}/3 lists)")
    else:
        feedback_parts.append(f"Low diversity ({distinct_lists}/3 lists)")

    # 4. Inbox Reduced (10 pts)
    reduction = START_INBOX - current_inbox
    # Note: If they moved 8 emails, reduction should be around 8.
    if reduction >= 8:
        score += 10
        feedback_parts.append(f"Inbox reduced by {reduction}")
    elif reduction >= 4:
        score += 5
        feedback_parts.append(f"Inbox partially reduced ({reduction})")
    else:
        feedback_parts.append(f"Inbox not significantly reduced ({reduction})")

    # 5. Briefing Email Drafted (20 pts)
    recipient_match = False
    subject_match = False
    body_match = False
    found_email = None

    target_recipient = metadata.get('briefing_recipient', 'backup@techcorp.org').lower()
    subject_keywords = metadata.get('subject_keywords', ['handoff', 'briefing'])
    known_lists = metadata.get('known_lists', ['sadev', 'ilug'])

    for email_obj in outgoing:
        if target_recipient in email_obj.get('to', '').lower():
            recipient_match = True
            found_email = email_obj
            break
    
    if recipient_match:
        score += 20
        feedback_parts.append("Briefing email found")
        
        # 6. Subject Line (10 pts)
        subj = found_email.get('subject', '').lower()
        if any(k in subj for k in subject_keywords):
            score += 10
            feedback_parts.append("Subject line correct")
        else:
            feedback_parts.append("Subject line missing keywords")

        # 7. Body Content (10 pts)
        body = found_email.get('body_snippet', '').lower()
        mentioned_lists = 0
        for lst in known_lists:
            if lst in body:
                mentioned_lists += 1
        
        if mentioned_lists >= 2:
            score += 10
            feedback_parts.append(f"Body mentions {mentioned_lists} lists")
        else:
            feedback_parts.append(f"Body missing list details (found {mentioned_lists})")

    else:
        feedback_parts.append("No email to backup@techcorp.org found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }