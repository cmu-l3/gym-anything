#!/usr/bin/env python3
"""
Verifier for emergency_communication_prep task.

Scoring Breakdown (100 pts total):
1. Folder Infrastructure (24 pts):
   - Incident-Infrastructure created (8)
   - Incident-Security created (8)
   - Incident-Software created (8)
2. Data Organization (20 pts):
   - Folders populated with >= 5 emails total (12)
   - Inbox reduced by >= 5 emails (8)
3. Draft Creation (44 pts):
   - Infra template correct (To + Subject) (10)
   - Security template correct (To + Subject) (10)
   - Software template correct (To + Subject) (10)
   - Quality: Body contains placeholders (3 pts per template, max 9) (9)
   - Completion email to CTO (To + Subject "Communication") (5)
4. Completion Report Content (12 pts):
   - CTO email references the created folders (12)

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_communication_prep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    placeholders = metadata.get('body_placeholders', [])

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

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # 1. Verify Folder Creation (24 pts)
    # ---------------------------------------------------------
    folders = result.get('folders', {})
    total_populated_count = 0
    
    for fname in ["Incident-Infrastructure", "Incident-Security", "Incident-Software"]:
        f_data = folders.get(fname, {})
        if f_data.get('exists', False):
            score += 8
            feedback.append(f"Folder '{fname}' created.")
            total_populated_count += f_data.get('count', 0)
        else:
            feedback.append(f"Folder '{fname}' MISSING.")

    # ---------------------------------------------------------
    # 2. Verify Data Organization (20 pts)
    # ---------------------------------------------------------
    # Folders populated
    if total_populated_count >= 5:
        score += 12
        feedback.append(f"Folders populated ({total_populated_count} emails).")
    elif total_populated_count >= 1:
        score += 4
        feedback.append(f"Folders partially populated ({total_populated_count} emails, expected 5+).")
    else:
        feedback.append("New folders are empty.")

    # Inbox reduced
    inbox_reduction = result.get('inbox_reduction', 0)
    if inbox_reduction >= 5:
        score += 8
        feedback.append(f"Inbox reduced by {inbox_reduction}.")
    elif inbox_reduction >= 3:
        score += 4
        feedback.append(f"Inbox partially reduced ({inbox_reduction}, expected 5+).")
    else:
        feedback.append("Inbox count not significantly reduced.")

    # ---------------------------------------------------------
    # 3. Verify Drafts (56 pts total including content)
    # ---------------------------------------------------------
    # Combine drafts and sent (in case agent sent them)
    all_messages = result.get('drafts', []) + result.get('sent_emails', [])
    
    # Helper to find message
    def find_message(recipient, subject_keyword):
        for msg in all_messages:
            if recipient in msg.get('to', '') and subject_keyword.lower() in msg.get('subject', '').lower():
                return msg
        return None

    # Check Infra Template
    infra_msg = find_message('infra-alerts@company.com', 'Infrastructure')
    if infra_msg:
        score += 10
        feedback.append("Infra template draft found.")
        # Check body quality
        body = infra_msg.get('body', '')
        hits = [p for p in placeholders if p in body]
        if len(hits) >= 1:
            score += 3
            feedback.append("Infra body has placeholders.")
    else:
        feedback.append("Infra template MISSING or invalid recipient/subject.")

    # Check Security Template
    sec_msg = find_message('security-team@company.com', 'Security')
    if sec_msg:
        score += 10
        feedback.append("Security template draft found.")
        body = sec_msg.get('body', '')
        hits = [p for p in placeholders if p in body]
        if len(hits) >= 1:
            score += 3
            feedback.append("Security body has placeholders.")
    else:
        feedback.append("Security template MISSING or invalid recipient/subject.")

    # Check Software Template
    soft_msg = find_message('engineering@company.com', 'Software')
    if soft_msg:
        score += 10
        feedback.append("Software template draft found.")
        body = soft_msg.get('body', '')
        hits = [p for p in placeholders if p in body]
        if len(hits) >= 1:
            score += 3
            feedback.append("Software body has placeholders.")
    else:
        feedback.append("Software template MISSING or invalid recipient/subject.")

    # Check Completion Report
    # Subject keywords can be flexible: "Emergency", "Incident", "Communication"
    cto_msg = None
    for kw in ['Emergency', 'Incident', 'Communication']:
        cto_msg = find_message('cto@company.com', kw)
        if cto_msg: break
        
    if cto_msg:
        score += 5
        feedback.append("Completion report to CTO found.")
        # Check content (references folders)
        body = cto_msg.get('body', '').lower()
        folder_mentions = 0
        if 'infrastructure' in body: folder_mentions += 1
        if 'security' in body: folder_mentions += 1
        if 'software' in body: folder_mentions += 1
        
        if folder_mentions >= 2: # Flexible
            score += 12
            feedback.append("Report content references created folders.")
        elif folder_mentions == 1:
            score += 6
            feedback.append("Report content partially references folders.")
    else:
        feedback.append("Completion report to CTO MISSING.")

    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }