#!/usr/bin/env python3
"""
Verifier for community_champion_identification task.

Criteria:
1. Folder 'Champion-Candidate' exists (20 pts)
2. Folder contains >= 2 emails (20 pts)
3. All emails in folder are from the SAME sender (20 pts) [Sender Consistency]
4. Draft/Sent email exists addressed to that sender (20 pts)
5. Subject line contains keywords (Champion, Community, Invite) (20 pts)

Anti-gaming:
- Checks that the folder was actually created (exists in result)
- Checks content consistency (can't just dump random emails)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_email(email_str):
    """Normalize email address for comparison."""
    if not email_str:
        return ""
    # Remove name parts, brackets, trim whitespace, lowercase
    # Simple extraction if < brackets > exist
    if '<' in email_str and '>' in email_str:
        start = email_str.find('<') + 1
        end = email_str.find('>')
        return email_str[start:end].strip().lower()
    return email_str.strip().lower()

def verify_community_champion_identification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = [k.lower() for k in metadata.get('subject_keywords', ['champion', 'community', 'invite'])]
    min_emails = metadata.get('min_emails', 2)

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

    # 1. Folder Exists (20 pts)
    folder_exists = result.get('folder_exists', False)
    if folder_exists:
        score += 20
        feedback.append("Folder 'Champion-Candidate' created.")
    else:
        feedback.append("Folder 'Champion-Candidate' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Content Analysis
    candidate_emails = result.get('candidate_emails', [])
    email_count = len(candidate_emails)
    
    # 2. Count Check (20 pts)
    if email_count >= min_emails:
        score += 20
        feedback.append(f"Folder contains sufficient emails ({email_count} >= {min_emails}).")
    elif email_count > 0:
        score += 10 # Partial
        feedback.append(f"Folder contains insufficient emails ({email_count} < {min_emails}).")
    else:
        feedback.append("Folder is empty.")

    # 3. Consistency Check (20 pts)
    # Extract senders
    senders = [e.get('from', '') for e in candidate_emails]
    unique_senders = set(senders)
    target_sender = None

    if email_count > 0:
        if len(unique_senders) == 1:
            score += 20
            target_sender = list(unique_senders)[0]
            feedback.append(f"Sender consistency verified. Target: {target_sender}")
        else:
            feedback.append(f"Inconsistent senders found in folder: {unique_senders}")
            # Identify the most frequent sender to try and give partial credit for outreach?
            # No, strict consistency required for 'isolating a contributor'.
    
    # 4. Outreach Verification (Draft/Sent)
    outbox = result.get('outbox_emails', [])
    outreach_found = False
    subject_correct = False
    
    if target_sender:
        for email_obj in outbox:
            # Check To address
            to_field = email_obj.get('to', '')
            # Simple check: is target_sender substring of To field?
            if target_sender in to_field or normalize_email(target_sender) in normalize_email(to_field):
                outreach_found = True
                
                # 5. Subject Check (20 pts)
                subj = email_obj.get('subject', '').lower()
                if any(kw in subj for kw in expected_keywords):
                    subject_correct = True
                break
    
    if outreach_found:
        score += 20
        feedback.append("Outreach email addressed to correct sender.")
    elif target_sender:
        feedback.append(f"No draft found addressed to {target_sender}.")
    else:
        feedback.append("Cannot verify outreach without consistent target sender.")

    if subject_correct:
        score += 20
        feedback.append("Subject line contains required keywords.")
    elif outreach_found:
        feedback.append("Subject line missing keywords.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }