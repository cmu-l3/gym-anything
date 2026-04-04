#!/usr/bin/env python3
"""
Verifier for trash_recovery task.

Scoring Criteria:
1. Recovery Folder Created (20 pts): A folder named like 'Recovered-Critical' exists.
2. Folder Populated (20 pts): Contains 3+ emails.
3. Trash Reduced (15 pts): Trash count decreased by at least 3.
4. Correct Content (15 pts): Emails in recovery folder match target lists (exmh-workers/ILUG).
5. Inbox Undisturbed (5 pts): Inbox count did not increase significantly (prevents "move all to inbox" gaming).
6. Confirmation Email (15 pts): Draft/Sent to ops-manager@techcorp.org.
7. Email Quality (10 pts): Subject/Body contains relevant keywords.

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trash_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    manager_email = metadata.get('manager_email', 'ops-manager@techcorp.org')

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
    feedback = []

    # Unpack result
    recovery_info = result.get('recovery_folder', {})
    custom_folders = result.get('custom_folders', {})
    initial_trash = result.get('initial_trash', 15)
    current_trash = result.get('current_trash', 15)
    initial_inbox = result.get('initial_inbox', 35)
    current_inbox = result.get('current_inbox', 35)
    outgoing = result.get('outgoing_emails', [])

    # 1. Recovery Folder Created (20 pts)
    # The python script in export_result tries to identify it by name containing "recover"
    # If not found there, check custom_folders keys
    folder_exists = recovery_info.get('exists', False)
    if not folder_exists:
        # Fallback check
        for name in custom_folders:
            if 'recover' in name.lower() or 'critical' in name.lower():
                folder_exists = True
                recovery_info['name'] = name
                recovery_info['count'] = custom_folders[name]
                break
    
    if folder_exists:
        score += 20
        feedback.append(f"Recovery folder '{recovery_info.get('name')}' created (+20)")
    else:
        feedback.append("No recovery folder found")

    # 2. Folder Populated (20 pts)
    rec_count = recovery_info.get('count', 0)
    if rec_count >= 3:
        score += 20
        feedback.append(f"Folder populated with {rec_count} emails (+20)")
    elif rec_count > 0:
        score += 10
        feedback.append(f"Folder partially populated ({rec_count} emails) (+10)")
    else:
        feedback.append("Recovery folder is empty")

    # 3. Trash Reduced (15 pts)
    trash_diff = initial_trash - current_trash
    if trash_diff >= 3:
        score += 15
        feedback.append(f"Trash reduced by {trash_diff} (+15)")
    elif trash_diff > 0:
        score += 5
        feedback.append(f"Trash reduced slightly ({trash_diff}) (+5)")
    else:
        feedback.append("Trash count did not decrease")

    # 4. Correct Content (15 pts)
    # Requires python script to have inspected headers
    targets_found = recovery_info.get('target_emails_found', 0)
    if targets_found >= 2:
        score += 15
        feedback.append(f"Confirmed {targets_found} target emails (ILUG/exmh) in recovery folder (+15)")
    elif targets_found == 1:
        score += 5
        feedback.append("Found 1 target email in recovery folder (+5)")
    elif folder_exists and rec_count > 0:
        feedback.append("Recovery folder contains emails, but they don't appear to be the correct target lists")

    # 5. Inbox Undisturbed (5 pts)
    # Prevent gaming by just moving trash to inbox
    inbox_growth = current_inbox - initial_inbox
    if inbox_growth <= 2:
        score += 5
        feedback.append("Inbox count stable (+5)")
    else:
        feedback.append(f"Inbox grew by {inbox_growth} (penalty for dumping trash to inbox)")

    # 6. Confirmation Email (15 pts)
    email_found = False
    email_content_score = 0
    
    for eml in outgoing:
        to = eml.get('to', '')
        if manager_email.lower() in to.lower():
            email_found = True
            
            # 7. Content Quality (10 pts)
            subj = eml.get('subject', '').lower()
            body = eml.get('body', '').lower()
            
            keywords = ['recover', 'restore', 'trash', 'delete', 'critical', 'list']
            if any(k in subj for k in keywords) or any(k in body for k in keywords):
                email_content_score = 10
            break

    if email_found:
        score += 15
        feedback.append(f"Confirmation email found to {manager_email} (+15)")
        if email_content_score > 0:
            score += 10
            feedback.append("Email content relevant (+10)")
        else:
            feedback.append("Email content vague")
    else:
        feedback.append(f"No email found to {manager_email}")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }