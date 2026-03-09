#!/usr/bin/env python3
"""
Verifier for sender_blocklist_recommendation task.

Scores criteria based on:
1. Folder Creation (Trusted & Blocklist)
2. Email Movement (Populating folders)
3. Report Drafting (Content analysis)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sender_blocklist_recommendation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('report_recipient', 'it-security@company.com').lower()
    trusted_folder_target = metadata.get('trusted_folder', 'Trusted-Senders').lower()
    blocklist_folder_target = metadata.get('blocklist_folder', 'Blocklist-Candidates').lower()
    min_trusted = metadata.get('min_trusted_move', 8)
    min_blocklist = metadata.get('min_blocklist_move', 5)

    # Copy result
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
    
    # Data from result
    custom_folders = {k.lower(): v for k, v in result.get('custom_folders', {}).items()}
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_emails = drafts + sent
    
    # ---------------------------------------------------------
    # Criterion 1 & 2: Folder Creation & Population (55 points)
    # ---------------------------------------------------------
    
    # Check Trusted-Senders
    trusted_exists = trusted_folder_target in custom_folders
    trusted_count = custom_folders.get(trusted_folder_target, 0)
    
    if trusted_exists:
        score += 10
        feedback.append(f"Folder '{metadata.get('trusted_folder')}' created.")
        if trusted_count >= min_trusted:
            score += 20
            feedback.append(f"Trusted folder populated with {trusted_count} emails (Target: {min_trusted}+).")
        elif trusted_count >= 3:
            score += 10
            feedback.append(f"Trusted folder partially populated with {trusted_count} emails.")
        else:
            feedback.append(f"Trusted folder empty or insufficient ({trusted_count}).")
    else:
        feedback.append(f"Folder '{metadata.get('trusted_folder')}' NOT found.")

    # Check Blocklist-Candidates
    blocklist_exists = blocklist_folder_target in custom_folders
    blocklist_count = custom_folders.get(blocklist_folder_target, 0)
    
    if blocklist_exists:
        score += 10
        feedback.append(f"Folder '{metadata.get('blocklist_folder')}' created.")
        if blocklist_count >= min_blocklist:
            score += 15
            feedback.append(f"Blocklist folder populated with {blocklist_count} emails (Target: {min_blocklist}+).")
        elif blocklist_count >= 2:
            score += 8
            feedback.append(f"Blocklist folder partially populated with {blocklist_count} emails.")
        else:
            feedback.append(f"Blocklist folder empty or insufficient ({blocklist_count}).")
    else:
        feedback.append(f"Folder '{metadata.get('blocklist_folder')}' NOT found.")

    # ---------------------------------------------------------
    # Criterion 3: Recommendation Email (45 points)
    # ---------------------------------------------------------
    
    target_email = None
    for email in all_emails:
        if target_recipient in email.get('to', '').lower():
            target_email = email
            break
            
    if target_email:
        score += 20
        feedback.append(f"Recommendation email drafted to {target_recipient}.")
        
        body = target_email.get('body', '') + " " + target_email.get('subject', '')
        
        # Check for domains (heuristic: look for dot-separated strings)
        # Exclude common noise like 'gmail.com' if strictly filtering, but simple regex is usually enough for context
        domain_pattern = r'\b[a-zA-Z0-9-]+\.[a-zA-Z]{2,}\b'
        domains_found = list(set(re.findall(domain_pattern, body)))
        # Filter out email addresses to just get domains if possible, or accept them as domains are part of addresses
        if len(domains_found) >= 2:
            score += 10
            feedback.append("Report contains multiple domain names.")
        else:
            feedback.append(f"Report missing specific domains (found {len(domains_found)}).")
            
        # Check for numeric statistics
        if re.search(r'\b\d+\b', body):
            score += 5
            feedback.append("Report contains numeric statistics.")
        else:
            feedback.append("Report missing numeric statistics.")
            
        # Check for terminology
        terms = ['blocklist', 'allowlist', 'whitelist', 'blacklist', 'block', 'reputation', 'quarantine', 'audit', 'recommend']
        found_terms = [t for t in terms if t in body.lower()]
        if len(found_terms) >= 2:
            score += 10
            feedback.append(f"Report uses security terminology ({', '.join(found_terms)}).")
        else:
            feedback.append("Report lacks specific security terminology.")
            
    else:
        feedback.append(f"No email found addressed to {target_recipient}.")

    # ---------------------------------------------------------
    # Anti-Gaming / Sanity Check
    # ---------------------------------------------------------
    # If no folders created AND no email drafted, force fail
    if score < 10:
        feedback.append("No significant progress detected.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }