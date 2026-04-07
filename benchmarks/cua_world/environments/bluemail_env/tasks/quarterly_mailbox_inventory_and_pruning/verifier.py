#!/usr/bin/env python3
"""
Verifier for quarterly_mailbox_inventory_and_pruning task.

SCORING CRITERIA:
1. Archive Folder (35 pts):
   - Folder matching 'Quarterly-Archive-Q4' exists (15 pts)
   - Folder contains 15+ emails (20 pts)
2. Inbox Pruning (15 pts):
   - Inbox count reduced to <= 35 (from 50)
3. Junk Handling (5 pts):
   - Junk count >= initial (didn't move spam back to inbox)
4. Report Draft (45 pts):
   - Email to 'it-admin@company.com' exists (15 pts)
   - Subject relevant (5 pts)
   - Body contains counts/numbers (15 pts)
   - Body has before/after context (10 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quarterly_maintenance(traj, env_info, task_info):
    """Verify quarterly mailbox maintenance task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    initial_inbox = metadata.get('initial_inbox_count', 50)
    initial_junk = metadata.get('initial_junk_count', 10)
    min_archived = metadata.get('min_archived_count', 15)
    
    # Load result
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

    # 1. Archive Folder Logic (35 pts)
    archive_info = result.get('archive_folder', {})
    if archive_info.get('is_match') or archive_info.get('exists'):
        score += 15
        feedback.append("Archive folder created")
        
        count = archive_info.get('count', 0)
        if count >= min_archived:
            score += 20
            feedback.append(f"Archive populated ({count} emails)")
        elif count >= 5:
            score += 10
            feedback.append(f"Archive partially populated ({count} emails)")
        else:
            feedback.append(f"Archive mostly empty ({count} emails)")
    else:
        feedback.append("Archive folder not found")

    # 2. Inbox Pruning (15 pts)
    inbox_count = result.get('inbox_count', 50)
    emails_moved = initial_inbox - inbox_count
    
    if inbox_count <= 35:
        score += 15
        feedback.append(f"Inbox pruned ({inbox_count} remaining)")
    elif inbox_count <= 45:
        score += 5
        feedback.append(f"Inbox slightly pruned ({inbox_count} remaining)")
    else:
        feedback.append(f"Inbox not significantly reduced ({inbox_count} remaining)")

    # 3. Junk Handling (5 pts)
    junk_count = result.get('junk_count', 0)
    if junk_count >= initial_junk:
        score += 5
        feedback.append("Junk count maintained")
    else:
        feedback.append("Warning: Junk count decreased (spam moved to inbox?)")

    # 4. Report Draft (45 pts)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_msgs = drafts + sent
    
    report_found = False
    best_report_score = 0
    
    for msg in all_msgs:
        msg_score = 0
        local_feedback = []
        
        # Check Recipient
        to = msg.get('to', '').lower()
        if 'it-admin@company.com' in to:
            msg_score += 15
            local_feedback.append("Recipient correct")
            
            # Check Subject
            subj = msg.get('subject', '').lower()
            if any(w in subj for w in ['quarterly', 'maintenance', 'report', 'inventory']):
                msg_score += 5
                local_feedback.append("Subject relevant")
            
            # Check Body Content
            body = msg.get('body', '').lower()
            
            # Look for numbers (counts)
            numbers = re.findall(r'\b\d+\b', body)
            if len(set(numbers)) >= 3:
                msg_score += 15
                local_feedback.append("Body contains counts")
            elif len(numbers) > 0:
                msg_score += 5
                local_feedback.append("Body contains some numbers")
                
            # Look for before/after keywords
            if ('before' in body or 'initial' in body) and ('after' in body or 'final' in body or 'current' in body):
                msg_score += 10
                local_feedback.append("Body has before/after context")
            
            if msg_score > best_report_score:
                best_report_score = msg_score
                report_found = True
    
    if report_found:
        score += best_report_score
        feedback.append(f"Report draft found (+{best_report_score} pts)")
    else:
        feedback.append("No valid report draft to it-admin@company.com found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }