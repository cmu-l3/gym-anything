#!/usr/bin/env python3
"""
Verifier for post_vacation_inbox_cleanup task.

SCORING CRITERIA (Total: 100 pts, Pass: 65 pts):
1. Emails Flagged (20 pts): At least 5 emails flagged/starred.
2. Emails Trashed (20 pts): At least 10 emails moved to Trash.
3. Archive Created (15 pts): 'Archive' or 'Archives' folder exists.
4. Archive Populated (15 pts): Archive folder contains 8+ emails.
5. Notification Drafted (30 pts): Email to 'team@projectalpha.org' with valid content.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_vacation_inbox_cleanup(traj, env_info, task_info):
    """
    Verify the inbox cleanup workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_flagged = metadata.get('min_flagged', 5)
    min_trashed = metadata.get('min_trashed', 10)
    min_archived = metadata.get('min_archived', 8)
    recipient = metadata.get('notification_recipient', 'team@projectalpha.org').lower()
    keywords = metadata.get('notification_keywords', ['back', 'return', 'vacation'])

    # Retrieve result file
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
    
    # ---------------------------------------------------------
    # Criterion 1: Flagged Emails (20 pts)
    # ---------------------------------------------------------
    flagged_count = result.get('flagged_count', 0)
    if flagged_count >= min_flagged:
        score += 20
        feedback_parts.append(f"Flags: {flagged_count} (Pass)")
    elif flagged_count >= 1:
        score += 10
        feedback_parts.append(f"Flags: {flagged_count} (Partial, need {min_flagged})")
    else:
        feedback_parts.append("Flags: 0 (Fail)")

    # ---------------------------------------------------------
    # Criterion 2: Trashed Emails (20 pts)
    # ---------------------------------------------------------
    # Prefer checking 'trash_moved_during_task' to prevent pre-existing files counting,
    # but since we clear trash in setup, total count is acceptable.
    trash_count = result.get('trash_count', 0)
    if trash_count >= min_trashed:
        score += 20
        feedback_parts.append(f"Trash: {trash_count} (Pass)")
    elif trash_count >= (min_trashed // 2):
        score += 10
        feedback_parts.append(f"Trash: {trash_count} (Partial, need {min_trashed})")
    else:
        feedback_parts.append(f"Trash: {trash_count} (Fail)")

    # ---------------------------------------------------------
    # Criterion 3: Archive Folder Created (15 pts)
    # ---------------------------------------------------------
    if result.get('archive_folder_exists'):
        score += 15
        feedback_parts.append(f"Archive folder: Created ({result.get('archive_folder_name')})")
    else:
        feedback_parts.append("Archive folder: Not found")

    # ---------------------------------------------------------
    # Criterion 4: Archive Populated (15 pts)
    # ---------------------------------------------------------
    archive_count = result.get('archive_email_count', 0)
    if archive_count >= min_archived:
        score += 15
        feedback_parts.append(f"Archived items: {archive_count} (Pass)")
    elif archive_count >= 1:
        score += 5
        feedback_parts.append(f"Archived items: {archive_count} (Partial, need {min_archived})")
    else:
        feedback_parts.append("Archived items: 0")

    # ---------------------------------------------------------
    # Criterion 5: Notification Email (30 pts)
    # ---------------------------------------------------------
    # Check both drafts and sent
    all_emails = result.get('drafts', []) + result.get('sent', [])
    
    found_email = False
    content_score = 0
    
    for email in all_emails:
        if recipient in email.get('to', '').lower():
            found_email = True
            
            # Check content quality
            subj = email.get('subject', '').lower()
            body = email.get('body', '').lower()
            combined = subj + " " + body
            
            # 10 pts for correct recipient (base)
            # +10 pts for relevant subject keywords
            # +10 pts for non-empty body
            
            current_email_score = 10
            
            if any(k in combined for k in keywords):
                current_email_score += 10
            
            if len(body) > 10: # At least a short sentence
                current_email_score += 10
                
            content_score = max(content_score, current_email_score)
    
    if found_email:
        score += content_score
        feedback_parts.append(f"Notification: Sent/Drafted ({content_score}/30 pts)")
    else:
        feedback_parts.append("Notification: Not found")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }