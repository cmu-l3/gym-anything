#!/usr/bin/env python3
"""
Verifier for kanban_workflow_setup task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kanban_workflow(traj, env_info, task_info):
    """
    Verify the Kanban workflow setup task.
    
    Scoring Criteria:
    1. Folder Creation (25 pts): All 5 specific folders exist.
    2. Inbox Reduction (20 pts): Inbox count reduced by at least 20.
    3. Distribution (15 pts): Each of the 5 folders has >= 2 emails.
    4. Volume (10 pts): Total emails in workflow folders >= 20.
    5. Announcement Email (20 pts): Draft/Sent to correct recipient.
    6. Email Quality (10 pts): Subject has "workflow", body mentions folders.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_folders = set(f.lower() for f in metadata.get('target_folders', []))
    target_recipient = metadata.get('recipient', '').lower()
    
    # Load Result
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
    
    # Data extraction
    found_folders = {k: v for k, v in result.get('folders', {}).items()}
    found_folder_names_lower = {k.lower(): k for k in found_folders.keys()}
    final_inbox = result.get('final_inbox_count', 50)
    initial_inbox = result.get('initial_inbox_count', 50)
    outgoing = result.get('outgoing_emails', [])

    # CRITERION 1: Folder Creation (Max 25)
    # Target: 01-Review, 02-Action-Required, 03-Waiting-Response, 04-Reference, 05-Done
    matched_folders = []
    for tf in target_folders:
        # Allow partial match (e.g. "01-Review" matches "01-review")
        if tf in found_folder_names_lower:
            matched_folders.append(found_folder_names_lower[tf])
    
    folder_score = len(matched_folders) * 5
    score += folder_score
    feedback.append(f"Folders created: {len(matched_folders)}/5 ({', '.join(matched_folders)})")

    # CRITERION 2: Inbox Reduction (Max 20)
    # Must move at least 20 emails out of inbox
    moved_count = initial_inbox - final_inbox
    if moved_count >= 20:
        score += 20
        feedback.append(f"Inbox reduced by {moved_count} (Pass)")
    elif moved_count >= 10:
        score += 10
        feedback.append(f"Inbox reduced by {moved_count} (Partial)")
    else:
        feedback.append(f"Inbox only reduced by {moved_count} (Fail)")

    # CRITERION 3: Distribution (Max 15)
    # Each valid workflow folder must have >= 2 emails
    folders_meeting_min = 0
    total_workflow_emails = 0
    
    for tf in target_folders:
        if tf in found_folder_names_lower:
            real_name = found_folder_names_lower[tf]
            count = found_folders[real_name]
            total_workflow_emails += count
            if count >= 2:
                folders_meeting_min += 1
    
    dist_score = folders_meeting_min * 3
    score += dist_score
    feedback.append(f"{folders_meeting_min}/5 folders meet minimum email count (2+)")

    # CRITERION 4: Total Volume (Max 10)
    # Sum of emails in the 5 target folders >= 20
    if total_workflow_emails >= 20:
        score += 10
        feedback.append(f"Total organized emails: {total_workflow_emails} (Pass)")
    elif total_workflow_emails >= 10:
        score += 5
        feedback.append(f"Total organized emails: {total_workflow_emails} (Partial)")
    else:
        feedback.append(f"Total organized emails: {total_workflow_emails} (Fail)")

    # CRITERION 5: Announcement Email Existence (Max 20)
    email_found = False
    best_email = None
    
    for email in outgoing:
        if target_recipient in str(email.get('to', '')).lower():
            email_found = True
            best_email = email
            break
            
    if email_found:
        score += 20
        feedback.append("Announcement email draft found")
    else:
        feedback.append("No announcement email found to correct recipient")

    # CRITERION 6: Email Content (Max 10)
    if email_found and best_email:
        content_score = 0
        subj = str(best_email.get('subject', '')).lower()
        body = str(best_email.get('body', '')).lower()
        
        # Check subject
        if "workflow" in subj:
            content_score += 5
        
        # Check body for folder mentions
        # We look for keywords like "Review", "Action", "Reference"
        keywords_found = 0
        check_words = ["review", "action", "waiting", "reference", "done"]
        for word in check_words:
            if word in body:
                keywords_found += 1
        
        if keywords_found >= 3:
            content_score += 5
            
        score += content_score
        feedback.append(f"Email content quality score: {content_score}/10")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }