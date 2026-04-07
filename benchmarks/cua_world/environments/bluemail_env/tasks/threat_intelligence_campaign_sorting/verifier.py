#!/usr/bin/env python3
"""
Verifier for threat_intelligence_campaign_sorting task.

Scores based on:
1. Creation of required folders (Threat-Financial, Threat-Commercial).
2. Semantic classification accuracy (checking keywords in moved emails).
3. Report creation (draft email with correct recipient and content).
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_keyword_density(text, keywords):
    """Returns the number of unique keywords found in the text."""
    text_lower = text.lower()
    count = 0
    found = []
    for kw in keywords:
        if kw in text_lower:
            count += 1
            found.append(kw)
    return count, found

def verify_threat_sorting(traj, env_info, task_info):
    """
    Verify that spam was sorted into Financial vs Commercial folders and reported.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    financial_keywords = metadata.get('financial_keywords', [])
    commercial_keywords = metadata.get('commercial_keywords', [])
    report_recipient = metadata.get('report_recipient', 'intel-team@security-corp.com')
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    folders = result.get('folders', {})
    drafts = result.get('drafts', [])
    
    score = 0
    feedback = []
    
    # Helper to find folder case-insensitively
    def get_folder_content(name_pattern):
        for fname, content in folders.items():
            if name_pattern.lower() in fname.lower():
                return fname, content
        return None, []

    # 1. Verify Financial Folder (35 pts)
    fin_name, fin_emails = get_folder_content("Financial")
    fin_subjects = []
    if fin_name:
        if len(fin_emails) >= 5:
            # Check content
            valid_count = 0
            for email in fin_emails:
                text = (email.get('subject', '') + " " + email.get('body', ''))
                hits, _ = check_keyword_density(text, financial_keywords)
                # If it has financial keywords OR it looks like a scam (heuristic)
                if hits >= 1:
                    valid_count += 1
                fin_subjects.append(email.get('subject', '').strip())
            
            if valid_count >= 3: # Allow some margin of error
                score += 35
                feedback.append(f"Financial folder '{fin_name}' contains {len(fin_emails)} emails ({valid_count} verified as financial).")
            else:
                score += 15
                feedback.append(f"Financial folder '{fin_name}' exists but contents do not seem to match keywords strongly.")
        else:
            score += 10
            feedback.append(f"Financial folder '{fin_name}' created but has too few emails ({len(fin_emails)}/5).")
    else:
        feedback.append("Financial threat folder not found.")

    # 2. Verify Commercial Folder (35 pts)
    com_name, com_emails = get_folder_content("Commercial")
    if com_name:
        if len(com_emails) >= 5:
            # Check content
            valid_count = 0
            for email in com_emails:
                text = (email.get('subject', '') + " " + email.get('body', ''))
                hits, _ = check_keyword_density(text, commercial_keywords)
                if hits >= 1:
                    valid_count += 1
            
            if valid_count >= 3:
                score += 35
                feedback.append(f"Commercial folder '{com_name}' contains {len(com_emails)} emails ({valid_count} verified as commercial).")
            else:
                score += 15
                feedback.append(f"Commercial folder '{com_name}' exists but contents do not match keywords strongly.")
        else:
            score += 10
            feedback.append(f"Commercial folder '{com_name}' created but has too few emails ({len(com_emails)}/5).")
    else:
        feedback.append("Commercial threat folder not found.")

    # 3. Verify Report (30 pts)
    report_found = False
    extracted_correctly = False
    
    for email in drafts:
        if report_recipient.lower() in str(email.get('to', '')).lower():
            report_found = True
            body = email.get('body', '').lower()
            subject = email.get('subject', '').lower()
            
            # Check if subject is relevant
            if "report" in subject or "fraud" in subject:
                score += 10
            
            # Check if body contains subjects from the financial folder
            matches = 0
            if fin_subjects:
                for subj in fin_subjects:
                    # Clean subject for matching (remove RE:, FWD:, simple whitespace)
                    clean_subj = re.sub(r'^(re|fwd):\s*', '', subj, flags=re.I).strip().lower()
                    if len(clean_subj) > 5 and clean_subj in body:
                        matches += 1
            
            if matches >= 3:
                score += 20
                extracted_correctly = True
                feedback.append(f"Report found with {matches} matching subject lines.")
            elif matches > 0:
                score += 10
                feedback.append(f"Report found but only {matches} subject lines matched.")
            else:
                feedback.append("Report found but could not verify extracted subject lines in body.")
            break
            
    if not report_found:
        feedback.append("No draft/sent email found addressed to expected recipient.")

    # Pass logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }