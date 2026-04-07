#!/usr/bin/env python3
"""
Verifier for client_user_agent_analytics task.

Verifies:
1. At least 3 folders created with 'UA-' prefix.
2. Content of these folders matches the implied User-Agent (fuzzy match).
3. Report draft exists with correct recipient and content.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_client_user_agent_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_folders = metadata.get('min_folders', 3)
    min_emails = metadata.get('min_emails_per_folder', 3)
    target_recipient = metadata.get('report_recipient', 'product-team@company.com')

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

    analysis = result.get('analysis', {})
    ua_folders = analysis.get('ua_folders', {})
    drafts = analysis.get('drafts', [])
    
    score = 0
    feedback = []

    # =========================================================
    # Criterion 1: Folders Created (20 pts)
    # =========================================================
    folder_names = list(ua_folders.keys())
    # Filter for valid format UA-Name
    valid_folders = [f for f in folder_names if f.startswith('UA-') and len(f) > 3]
    
    if len(valid_folders) >= min_folders:
        score += 20
        feedback.append(f"Created {len(valid_folders)} UA folders: {', '.join(valid_folders)}")
    elif len(valid_folders) > 0:
        score += 10
        feedback.append(f"Created {len(valid_folders)} UA folders (needed {min_folders})")
    else:
        feedback.append("No 'UA-*' folders found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # =========================================================
    # Criterion 2: Folder Content Accuracy (60 pts max)
    # =========================================================
    # We check up to 3 folders. Each worth 20 points.
    # Logic: Extract client name from folder (e.g., UA-Mutt -> mutt).
    # Check if headers contain that name.
    
    folder_scores = 0
    folders_checked = 0
    
    for folder in valid_folders[:3]: # check top 3
        folders_checked += 1
        client_target = folder[3:].lower() # remove UA-
        emails = ua_folders[folder]
        
        if len(emails) < min_emails:
            feedback.append(f"Folder {folder} has too few emails ({len(emails)}/{min_emails}).")
            continue
            
        # Check accuracy
        matches = 0
        for email_data in emails:
            raw_headers = email_data.get('raw', '').lower()
            # Simple fuzzy match: does the client name appear in the UA/Mailer headers?
            if client_target in raw_headers:
                matches += 1
            # Handle common aliases if necessary (optional logic)
            elif client_target == 'outlook' and 'microsoft' in raw_headers:
                matches += 1
            elif client_target == 'apple' and 'mac os' in raw_headers:
                matches += 1
        
        accuracy = matches / len(emails)
        if accuracy >= 0.6: # Allow some noise
            folder_scores += 20
            feedback.append(f"Folder {folder}: Validated ({matches}/{len(emails)} matches)")
        else:
            feedback.append(f"Folder {folder}: Low accuracy ({matches}/{len(emails)} matches for '{client_target}')")

    score += folder_scores

    # =========================================================
    # Criterion 3: Report Draft (20 pts)
    # =========================================================
    report_found = False
    for draft in drafts:
        # Check recipient
        to_field = draft.get('to', '').lower()
        if target_recipient in to_field:
            report_found = True
            score += 10
            feedback.append("Report draft found to correct recipient.")
            
            # Check content for folder names
            body = draft.get('body', '').lower()
            subject = draft.get('subject', '').lower()
            
            # 10 pts for mentioning client names found
            mentioned = [f[3:] for f in valid_folders if f[3:].lower() in body or f[3:].lower() in subject]
            if len(mentioned) > 0:
                score += 10
                feedback.append(f"Report mentions clients: {', '.join(mentioned)}")
            break
    
    if not report_found:
        feedback.append("No draft found to product-team@company.com")

    # =========================================================
    # Final Calculation
    # =========================================================
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }