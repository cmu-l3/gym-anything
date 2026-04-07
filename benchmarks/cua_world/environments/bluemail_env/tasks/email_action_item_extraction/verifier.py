#!/usr/bin/env python3
"""
Verifier for email_action_item_extraction task.

Verifies:
1. 'Action-Required' folder creation.
2. Population of that folder with actionable emails.
3. Creation of a summary email (draft or sent) with list formatting.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_action_item_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_folder = metadata.get('target_folder', 'Action-Required')
    min_move = metadata.get('min_emails_to_move', 5)
    summary_recipient = metadata.get('summary_recipient', 'ga@example.com')
    subject_keywords = metadata.get('subject_keywords', ["action", "todo", "tasks"])
    action_patterns = metadata.get('action_patterns', ["please", "todo"])

    # Load initial inbox count from file passed via env is tricky, so we rely on constant knowledge
    # or we could have exported it. Let's assume baseline 50.
    baseline_inbox = 50 

    # Fetch result
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

    # --- Criterion 1: Folder Creation (20 pts) ---
    if result.get('folder_exists'):
        score += 20
        feedback.append(f"Folder '{target_folder}' created (+20).")
    else:
        feedback.append(f"Folder '{target_folder}' NOT found.")

    # --- Criterion 2: Emails Moved (20 pts) ---
    count = result.get('folder_email_count', 0)
    if count >= min_move:
        score += 20
        feedback.append(f"Moved {count} emails into folder (+20).")
    elif count >= 3:
        score += 10
        feedback.append(f"Moved {count} emails (partial credit) (+10).")
    else:
        feedback.append(f"Only {count} emails moved (target: {min_move}).")

    # --- Criterion 3: Semantic Actionability Check (15 pts) ---
    # Check if moved emails actually contain action keywords
    emails_content = result.get('folder_emails_content', [])
    actionable_count = 0
    if emails_content:
        for email in emails_content:
            text = (email.get('subject', '') + " " + email.get('body', '')).lower()
            if any(p in text for p in action_patterns):
                actionable_count += 1
        
        # Calculate percentage
        percent = actionable_count / len(emails_content) if len(emails_content) > 0 else 0
        if percent >= 0.60:
            score += 15
            feedback.append(f"Moved emails are actionable ({int(percent*100)}%) (+15).")
        elif percent >= 0.40:
            score += 8
            feedback.append(f"Some moved emails are actionable ({int(percent*100)}%) (+8).")
        else:
            feedback.append(f"Moved emails seem random/non-actionable ({int(percent*100)}%).")
    else:
        if count > 0:
            feedback.append("Could not analyze email content.")

    # --- Criterion 4: Inbox Reduced (5 pts) ---
    final_inbox = result.get('final_inbox_count', 50)
    if final_inbox < baseline_inbox:
        score += 5
        feedback.append("Inbox count reduced (+5).")
    
    # --- Criterion 5: Summary Email Existence (20 pts) ---
    all_outgoing = result.get('drafts', []) + result.get('sent', [])
    summary_email = None
    
    for email in all_outgoing:
        if summary_recipient.lower() in email.get('to', '').lower():
            summary_email = email
            break
            
    if summary_email:
        score += 20
        feedback.append(f"Summary email found to {summary_recipient} (+20).")
    else:
        feedback.append(f"No email found addressed to {summary_recipient}.")

    # --- Criterion 6: Subject Line (10 pts) ---
    if summary_email:
        subj = summary_email.get('subject', '').lower()
        if any(k in subj for k in subject_keywords):
            score += 10
            feedback.append("Subject line contains keywords (+10).")
        else:
            feedback.append(f"Subject '{subj}' missing keywords like {subject_keywords}.")

    # --- Criterion 7: Body List Formatting (10 pts) ---
    if summary_email:
        body = summary_email.get('body', '')
        # Regex for list items: lines starting with number+dot/paren or dash/bullet
        list_items = re.findall(r'(?:^|\n)\s*(?:\d+[\.\)]|[-*•])\s+\S+', body)
        if len(list_items) >= 3:
            score += 10
            feedback.append(f"Body contains list items ({len(list_items)} items) (+10).")
        else:
            feedback.append("Body does not appear to contain a structured list.")

    # Pass Threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }