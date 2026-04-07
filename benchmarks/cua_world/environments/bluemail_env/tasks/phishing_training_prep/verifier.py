#!/usr/bin/env python3
"""
Verifier for phishing_training_prep task.

Scoring Breakdown (100 pts total):
1. Training-Examples folder created (15 pts)
2. Folder populated with 5+ emails (20 pts)
   - Partial credit for 2-4 emails
3. Source Check: Emails are from spam corpus (10 pts)
   - Inferred from subject lines/senders matching known spam patterns
4. Draft/Sent email exists (10 pts)
5. Recipient is correct (10 pts)
6. Subject is relevant (10 pts)
7. Content Analysis: Technique diversity (20 pts)
   - Mentions 3+ distinct categories of spam techniques
8. Body length > 100 chars (5 pts)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phishing_training_prep(traj, env_info, task_info):
    """Verify the phishing training preparation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_folder_base = metadata.get('target_folder', 'Training-Examples').lower()
    min_examples = metadata.get('min_examples', 5)
    target_recipient = metadata.get('recipient', 'all-staff@company.com')
    technique_keywords = metadata.get('technique_keywords', {})
    
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

    # 1. Folder Creation (15 pts)
    folder_found = result.get('training_folder_found', False)
    folder_name = result.get('training_folder_name', 'None')
    
    if folder_found:
        score += 15
        feedback.append(f"Folder '{folder_name}' created.")
    else:
        feedback.append("No training folder found.")

    # 2. Folder Population (20 pts)
    count = result.get('training_email_count', 0)
    if count >= min_examples:
        score += 20
        feedback.append(f"Folder populated with {count} emails.")
    elif count >= 2:
        score += 10
        feedback.append(f"Folder partially populated ({count}/{min_examples}).")
    else:
        feedback.append(f"Folder empty or insufficient emails ({count}).")

    # 3. Source Check (10 pts) - Are they spam?
    # Simple heuristic: Real spam in this corpus often has specific subjects or blank subjects
    # We'll check if at least some emails have subjects typical of the corpus or simply exist
    # Since we can't easily cross-reference IDs without complex mapping, we award points if
    # the folder is populated and we assume agent followed instructions to move from Junk.
    # To be safer, we check if they are NOT the ham emails (ham usually has [List-Name] prefixes).
    
    training_emails = result.get('training_emails', [])
    spam_indicator_score = 0
    for email in training_emails:
        subj = email.get('subject', '').lower()
        # Ham lists in this corpus often have these tags
        if any(x in subj for x in ['[sadev]', '[ilug]', '[zzzzteana]', '[satalk]']):
            continue # Likely ham
        spam_indicator_score += 1
    
    if count > 0 and spam_indicator_score >= 3:
        score += 10
        feedback.append("Selected emails appear to be from spam corpus.")
    elif count > 0:
        feedback.append("Selected emails might be mixed with ham.")

    # 4. Draft/Sent Email Exists (10 pts)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_emails = drafts + sent
    
    valid_email = None
    
    # Find the best candidate email
    for email in all_emails:
        if target_recipient in email.get('to', '').lower():
            valid_email = email
            break
            
    if not valid_email and all_emails:
        # Fallback: check if any email mentions training
        for email in all_emails:
            if 'training' in email.get('subject', '').lower():
                valid_email = email
                break

    if valid_email:
        score += 10
        feedback.append("Draft/Sent email found.")
    elif all_emails:
        feedback.append("Draft exists but recipient/subject unclear.")
    else:
        feedback.append("No draft or sent email found.")

    # 5. Recipient Check (10 pts)
    if valid_email and target_recipient in valid_email.get('to', '').lower():
        score += 10
        feedback.append(f"Recipient correct ({target_recipient}).")
    elif valid_email:
        feedback.append(f"Incorrect recipient: {valid_email.get('to', 'None')}")

    # 6. Subject Relevance (10 pts)
    if valid_email:
        subj = valid_email.get('subject', '').lower()
        if any(w in subj for w in ['training', 'phishing', 'awareness', 'security', 'spam']):
            score += 10
            feedback.append("Subject is relevant.")
        else:
            feedback.append("Subject missing key terms.")

    # 7. Technique Diversity (20 pts)
    if valid_email:
        body = valid_email.get('body', '').lower()
        subject = valid_email.get('subject', '').lower()
        full_text = f"{subject} {body}"
        
        categories_found = set()
        for cat, keywords in technique_keywords.items():
            if any(k in full_text for k in keywords):
                categories_found.add(cat)
        
        if len(categories_found) >= 3:
            score += 20
            feedback.append(f"Techniques covered: {', '.join(categories_found)}")
        elif len(categories_found) >= 1:
            score += 10
            feedback.append(f"Partial techniques covered: {', '.join(categories_found)}")
        else:
            feedback.append("No specific spam techniques identified in text.")
            
        # 8. Body Length (5 pts)
        if len(body) > 100:
            score += 5
        else:
            feedback.append("Email body too short.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }