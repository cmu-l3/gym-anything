#!/usr/bin/env python3
"""
Verifier for priority_flagging_and_digest task.

Scoring Criteria (100 pts total):
1. Priority-Queue Folder (35 pts):
   - Folder exists: 15 pts
   - Populated (>=5 emails): 20 pts (Partial: 10 pts for >=3)
2. Flagging/Starring (15 pts):
   - >=3 flagged emails in Inbox: 15 pts (Partial: 8 pts for >=1)
3. Digest Email (45 pts):
   - Email exists (Draft/Sent) to correct recipient: 20 pts
   - Subject contains keywords: 10 pts
   - Body contains mailing list references: 15 pts
4. Inbox Reduction (5 pts):
   - Inbox count reduced by >=5: 5 pts

Pass Threshold: 65/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_priority_flagging_and_digest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('digest_recipient', 'standup@devops-team.org').lower()
    min_moved = metadata.get('min_moved_count', 5)
    min_flagged = metadata.get('min_flagged_count', 3)
    
    # 1. Load Result
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
    feedback = []

    # --- Criterion 1: Priority-Queue Folder (35 pts) ---
    pq_exists = result.get('priority_queue_exists', False)
    pq_count = result.get('priority_queue_count', 0)
    
    if pq_exists:
        score += 15
        feedback.append("Priority-Queue folder created (+15)")
        if pq_count >= min_moved:
            score += 20
            feedback.append(f"Folder populated with {pq_count} emails (+20)")
        elif pq_count >= 3:
            score += 10
            feedback.append(f"Folder partially populated ({pq_count} emails) (+10)")
        else:
            feedback.append(f"Folder exists but mostly empty ({pq_count} emails)")
    else:
        feedback.append("Priority-Queue folder NOT found")

    # --- Criterion 2: Flagging (15 pts) ---
    flagged_count = result.get('inbox_flagged_count', 0)
    if flagged_count >= min_flagged:
        score += 15
        feedback.append(f"Flagged {flagged_count} emails (+15)")
    elif flagged_count >= 1:
        score += 8
        feedback.append(f"Flagged {flagged_count} emails (Partial +8)")
    else:
        feedback.append("No emails flagged/starred in inbox")

    # --- Criterion 3: Digest Email (45 pts) ---
    digest_candidates = result.get('digest_emails', [])
    valid_digest = None
    
    for email in digest_candidates:
        if target_recipient in email.get('to', '').lower():
            valid_digest = email
            break
            
    if valid_digest:
        score += 20
        feedback.append("Digest email found addressed to team (+20)")
        
        # Check Subject
        subj = valid_digest.get('subject', '').lower()
        keywords = metadata.get('digest_keywords', ['digest', 'morning', 'briefing'])
        if any(k in subj for k in keywords):
            score += 10
            feedback.append("Subject contains relevant keywords (+10)")
        else:
            feedback.append(f"Subject '{subj}' missing keywords")
            
        # Check Body for Mailing List mentions
        body = valid_digest.get('body', '').lower()
        lists = metadata.get('mailing_lists', [])
        found_lists = [l for l in lists if l.lower() in body]
        if len(found_lists) >= 2:
            score += 15
            feedback.append(f"Body references {len(found_lists)} mailing lists (+15)")
        elif len(found_lists) == 1:
            score += 5
            feedback.append("Body references 1 mailing list (+5)")
        else:
            feedback.append("Body missing mailing list context")
    else:
        feedback.append("No digest email found addressed to " + target_recipient)

    # --- Criterion 4: Inbox Reduction (5 pts) ---
    initial = result.get('initial_inbox_count', 50)
    current = result.get('inbox_count', 50)
    if (initial - current) >= 5:
        score += 5
        feedback.append("Inbox count reduced (+5)")

    # --- Final Result ---
    # Anti-gaming: Do Nothing check
    if not pq_exists and flagged_count == 0 and not valid_digest:
        score = 0
        feedback = ["Do Nothing detected (No folder, flags, or draft)"]

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }