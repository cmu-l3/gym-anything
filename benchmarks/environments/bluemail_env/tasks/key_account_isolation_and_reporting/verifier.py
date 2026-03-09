#!/usr/bin/env python3
"""
Verifier for key_account_isolation_and_reporting task.

Scoring Breakdown:
- Folder Creation (10 pts): 'VIP-Accounts' exists.
- Isolation Precision (20 pts): Emails in folder match VIP list (no false positives).
- Isolation Recall (25 pts): All VIP emails found and moved.
- Draft Created (15 pts): Email to director@company.com exists.
- Report Accuracy (30 pts): Subject lines of VIP emails are listed in the report body.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_key_account_isolation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    ground_truth = result.get('ground_truth', {})
    vip_senders = set(s.lower() for s in ground_truth.get('vip_senders', []))
    expected_emails = ground_truth.get('expected_emails', [])
    
    # --- Criterion 1: Folder Creation (10 pts) ---
    if result.get('vip_folder_exists', False):
        score += 10
        feedback.append("VIP-Accounts folder created.")
    else:
        feedback.append("VIP-Accounts folder NOT found.")
        # If folder missing, likely failed isolation too, but we check anyway
    
    # --- Criterion 2: Isolation (Precision & Recall) (45 pts) ---
    found_emails = result.get('vip_folder_emails', [])
    
    # Precision: Are items in the folder actually from VIPs?
    false_positives = 0
    true_positives = 0
    
    for email in found_emails:
        sender = email.get('sender', '').lower()
        if sender in vip_senders:
            true_positives += 1
        else:
            false_positives += 1
            
    if len(found_emails) > 0:
        if false_positives == 0:
            score += 20
            feedback.append("Precision check passed: All items in folder are from VIPs.")
        else:
            # Partial credit for precision?
            # 20 points * (TP / (TP + FP))
            precision_score = int(20 * (true_positives / len(found_emails)))
            score += precision_score
            feedback.append(f"Precision check failed: {false_positives} non-VIP emails found in folder.")
    elif result.get('vip_folder_exists', False):
         feedback.append("VIP folder is empty.")

    # Recall: Did we capture all expected VIP emails?
    total_expected = len(expected_emails)
    if total_expected > 0:
        if true_positives >= total_expected:
            score += 25
            feedback.append(f"Recall check passed: All {total_expected} VIP emails isolated.")
        else:
            # Partial recall
            recall_score = int(25 * (true_positives / total_expected))
            score += recall_score
            feedback.append(f"Recall check: {true_positives}/{total_expected} VIP emails isolated.")
    else:
        # Edge case: No emails matched? Should not happen with setup logic.
        score += 25
        feedback.append("No VIP emails were present in inbox (setup error?), awarding points.")

    # --- Criterion 3 & 4: Reporting (45 pts) ---
    drafts = result.get('drafts_sent', [])
    target_recipient = "director@company.com"
    
    found_report = None
    for d in drafts:
        if target_recipient in d.get('to', ''):
            found_report = d
            break
            
    if found_report:
        score += 15
        feedback.append("Report draft to director found.")
        
        # Content Check
        body = found_report.get('body', '').lower()
        subject_lines_found = 0
        expected_subjects = [e['subject'].lower() for e in expected_emails]
        
        # We need to be careful about matching. Simple substring check of subject line in body.
        # Filter out empty subjects or very short common ones to avoid false matches if possible,
        # but SpamAssassin subjects are usually distinct.
        for subj in expected_subjects:
            # Clean up Re: Fwd: etc
            clean_subj = re.sub(r'^(re|fwd):\s*', '', subj).strip()
            if clean_subj and clean_subj in body:
                subject_lines_found += 1
        
        if len(expected_subjects) > 0:
            match_rate = subject_lines_found / len(expected_subjects)
            # 30 points for accuracy
            report_score = int(30 * match_rate)
            score += report_score
            feedback.append(f"Report content accuracy: {int(match_rate*100)}% of subjects found in body.")
    else:
        feedback.append("No draft email found addressed to director@company.com.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }