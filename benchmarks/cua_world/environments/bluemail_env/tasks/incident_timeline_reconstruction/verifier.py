#!/usr/bin/env python3
"""
Verifier for Incident Timeline Reconstruction task.

Verification Logic:
1. Evidence Folder (20pts): Check if 'Postmortem-Evidence' exists.
2. Evidence Collection (20pts): Check if folder contains 8+ emails.
3. Inbox Cleanup (10pts): Check if inbox count reduced by >= 8.
4. Report Drafted (25pts): Check for email to 'postmortem@sre-team.org'.
5. Report Content (15pts): Check if report references real email subjects from corpus.
6. Report Language (10pts): Check for timeline-related keywords.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_incident_timeline(traj, env_info, task_info):
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_subjects = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Load corpus subjects for content verification
        copy_from_env("/tmp/corpus_subjects.txt", temp_subjects.name)
        with open(temp_subjects.name, 'r', encoding='utf-8', errors='ignore') as f:
            corpus_subjects = [line.strip().lower() for line in f if line.strip()]
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_subjects.name): os.unlink(temp_subjects.name)

    # 2. Extract Data
    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('target_recipient', 'postmortem@sre-team.org')
    timeline_keywords = metadata.get('timeline_keywords', [])
    initial_inbox = metadata.get('initial_inbox_count', 50)
    
    score = 0
    feedback = []

    # --- Criterion 1: Evidence Folder (20pts) ---
    if result.get("evidence_folder_found"):
        score += 20
        feedback.append(" Evidence folder created.")
    else:
        feedback.append(" Evidence folder NOT found.")

    # --- Criterion 2: Evidence Collection (20pts) ---
    evidence_count = result.get("evidence_folder_count", 0)
    if evidence_count >= 8:
        score += 20
        feedback.append(f" {evidence_count} emails collected (Target: 8+).")
    elif evidence_count >= 4:
        score += 10
        feedback.append(f" {evidence_count} emails collected (Partial credit).")
    else:
        feedback.append(f" Only {evidence_count} emails in evidence folder.")

    # --- Criterion 3: Inbox Cleanup (10pts) ---
    current_inbox = result.get("current_inbox_count", 50)
    moved_count = initial_inbox - current_inbox
    if moved_count >= 8:
        score += 10
        feedback.append(" Inbox reduced significantly.")
    else:
        feedback.append(f" Inbox barely changed (-{moved_count}).")

    # --- Criterion 4: Report Drafted (25pts) ---
    report_found = False
    report_body = ""
    report_subject = ""
    
    for email in result.get("drafts_and_sent", []):
        if target_recipient in email.get("to", "").lower() or target_recipient in email.get("body", "").lower():
            report_found = True
            report_body = email.get("body", "").lower()
            report_subject = email.get("subject", "").lower()
            break
            
    if report_found:
        score += 25
        feedback.append(" Report draft found.")
    else:
        feedback.append(" No report to 'postmortem@sre-team.org' found.")

    # --- Criterion 5: Report Content (References) (15pts) ---
    # Check if the report mentions subjects from the actual emails
    if report_found:
        matches = 0
        # Check for significant substrings (clean subjects)
        clean_body = report_body.replace('\n', ' ').replace('\r', '')
        
        for subj in corpus_subjects:
            # Skip very short subjects to avoid false positives
            if len(subj) < 10: continue
            
            # Simple keyword matching isn't enough, check for significant phrase overlap
            # Split subject into main words
            words = [w for w in subj.split() if len(w) > 4]
            if len(words) >= 2:
                # If 2 consecutive significant words from a subject appear in body
                phrase = " ".join(words[:2])
                if phrase in clean_body:
                    matches += 1
                    
        if matches >= 3:
            score += 15
            feedback.append(f" Report references {matches} specific emails.")
        elif matches >= 1:
            score += 8
            feedback.append(f" Report references {matches} email (Partial).")
        else:
            feedback.append(" Report content vague; no specific email references found.")
    
    # --- Criterion 6: Report Language (10pts) ---
    if report_found:
        found_keywords = [k for k in timeline_keywords if k in report_body or k in report_subject]
        if found_keywords:
            score += 10
            feedback.append(" Report uses timeline terminology.")
        else:
            feedback.append(" Report structure unclear (missing timeline keywords).")

    # --- Anti-Gaming / Sanity Check ---
    if score > 0 and not result.get("bluemail_running", False):
        # Penalty if app crashed or closed? 
        # Actually, BlueMail might be closed gracefully, so we don't zero out,
        # but the task usually expects it open.
        feedback.append(" (Note: BlueMail was not running at verification time)")

    final_result = {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }
    
    return final_result