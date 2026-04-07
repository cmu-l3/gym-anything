#!/usr/bin/env python3
"""
Verifier for new_hire_onboarding_package task.

Scoring Breakdown (100 points total):
1. Onboarding folder created (20 pts)
   - Must contain "onboard" (case-insensitive) in name.
2. Folder populated (20 pts)
   - >= 8 emails: 20 pts
   - 4-7 emails: 10 pts
   - 1-3 emails: 5 pts
3. Welcome email drafted/sent (20 pts)
   - To: alex.chen@techcorp.org
4. Welcome email subject quality (10 pts)
   - Contains "welcome", "onboard", etc.
5. Welcome email body guidance (15 pts)
   - Mentions the folder name AND has > 20 words.
6. Team notification (15 pts)
   - To/CC: dev-team@techcorp.org (can be same email or separate).

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_new_hire_onboarding_package(traj, env_info, task_info):
    """Verify that the onboarding package was created and emails drafted."""
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from JSON
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

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('primary_recipient', 'alex.chen@techcorp.org').lower()
    team_recipient = metadata.get('team_list', 'dev-team@techcorp.org').lower()
    min_emails = metadata.get('min_emails_to_curate', 8)
    
    score = 0
    feedback = []

    # ================================================================
    # Criterion 1: Folder Creation (20 pts)
    # ================================================================
    folder_found = result.get('onboarding_folder_found', False)
    folder_name = result.get('onboarding_folder_name', "")
    
    if folder_found:
        score += 20
        feedback.append(f"Folder '{folder_name}' created.")
    else:
        feedback.append("No folder containing 'onboard' found.")

    # ================================================================
    # Criterion 2: Folder Population (20 pts)
    # ================================================================
    count = result.get('onboarding_email_count', 0)
    
    if count >= min_emails:
        score += 20
        feedback.append(f"Folder populated with {count} emails (Target: {min_emails}+).")
    elif count >= 4:
        score += 10
        feedback.append(f"Folder partially populated with {count} emails (Target: {min_emails}+).")
    elif count >= 1:
        score += 5
        feedback.append(f"Folder has very few emails ({count}).")
    else:
        feedback.append("Onboarding folder is empty.")

    # ================================================================
    # Email Analysis (Criteria 3-6)
    # ================================================================
    outgoing = result.get('outgoing_emails', [])
    
    welcome_email = None
    team_notified = False
    
    # Search for relevant emails
    for email in outgoing:
        to_field = email.get('to', '').lower()
        cc_field = email.get('cc', '').lower()
        bcc_field = email.get('bcc', '').lower()
        all_recipients = f"{to_field} {cc_field} {bcc_field}"
        
        # Check for welcome email candidate
        if target_recipient in all_recipients:
            # Pick the best candidate (longest body preferably) if multiple
            if welcome_email is None or len(email.get('body', '')) > len(welcome_email.get('body', '')):
                welcome_email = email
        
        # Check for team notification
        if team_recipient in all_recipients:
            team_notified = True

    # Criterion 3: Welcome Email Drafted (20 pts)
    if welcome_email:
        score += 20
        feedback.append("Welcome email drafted for Alex Chen.")
        
        # Criterion 4: Subject Quality (10 pts)
        subj = welcome_email.get('subject', '').lower()
        keywords = ['welcome', 'onboard', 'reading', 'start', 'materials']
        if any(k in subj for k in keywords):
            score += 10
            feedback.append("Subject line is appropriate.")
        else:
            feedback.append(f"Subject line '{subj}' missing keywords.")

        # Criterion 5: Body Guidance (15 pts)
        body = welcome_email.get('body', '').lower()
        word_count = welcome_email.get('body_word_count', 0)
        
        # Check if folder is mentioned
        folder_mentioned = folder_name.lower() in body or "folder" in body or "reading" in body
        
        if folder_mentioned and word_count >= 20:
            score += 15
            feedback.append("Body content provides guidance.")
        elif folder_mentioned:
            score += 5
            feedback.append("Body mentions folder but is too short (<20 words).")
        else:
            feedback.append("Body does not clearly reference the reading folder.")

    else:
        feedback.append(f"No email found addressed to {target_recipient}.")

    # Criterion 6: Team Notification (15 pts)
    if team_notified:
        score += 15
        feedback.append("Team notification sent (CC or separate email).")
    else:
        feedback.append(f"Team ({team_recipient}) was not notified.")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }