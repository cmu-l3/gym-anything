#!/usr/bin/env python3
"""
Verifier for legal_hold_preservation task.

Scoring Breakdown (100 pts):
- 15 pts: Legal-Hold folder created
- 25 pts: Recall (Percentage of actual matching emails found and preserved)
- 10 pts: Precision (Percentage of preserved emails that are actual matches)
- 10 pts: Cross-folder search evidence (At least one Junk email preserved)
- 15 pts: Certification email drafted/sent
- 10 pts: Certification subject contains case reference
- 15 pts: Certification body quality (counts, keywords, confirmation)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legal_hold_preservation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('recipient', 'legal-compliance@company.com')
    case_ref = metadata.get('case_reference', 'IP-2024-0847')

    # 1. Load Task Result
    task_res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", task_res_file.name)
        with open(task_res_file.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(task_res_file.name):
            os.unlink(task_res_file.name)

    # 2. Load Ground Truth (calculated by setup script)
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth_matches.json", gt_file.name)
        with open(gt_file.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        # Fallback if ground truth missing (should not happen if setup ran)
        logger.error(f"Missing ground truth: {e}")
        ground_truth = {"total_matches": 1, "inbox_matches": 0, "junk_matches": 0}
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Folder Creation (15 pts) ---
    if res.get("folder_exists"):
        score += 15
        feedback.append("Legal-Hold folder created.")
    else:
        feedback.append("Legal-Hold folder NOT found.")

    # --- Criterion 2: Recall (25 pts) ---
    # How many of the ground truth matches did the agent find?
    # Note: result["true_positives"] counts preserved files that match keywords
    tp = res.get("true_positives", 0)
    total_gt = ground_truth.get("total_matches", 1) # Avoid div by zero
    
    recall = tp / total_gt if total_gt > 0 else 0
    if recall >= 0.7:
        score += 25
        feedback.append(f"Excellent recall ({tp}/{total_gt} matches found).")
    elif recall >= 0.4:
        score += 15
        feedback.append(f"Moderate recall ({tp}/{total_gt} matches found).")
    elif recall > 0:
        score += 8
        feedback.append(f"Poor recall ({tp}/{total_gt} matches found).")
    else:
        feedback.append("No matching emails preserved.")

    # --- Criterion 3: Precision (10 pts) ---
    # Did the agent just dump everything?
    folder_count = res.get("folder_email_count", 0)
    if folder_count > 0:
        precision = tp / folder_count
        if precision >= 0.8:
            score += 10
            feedback.append("High precision preservation.")
        elif precision >= 0.5:
            score += 5
            feedback.append("Mixed precision - some non-relevant emails moved.")
        else:
            feedback.append("Low precision - too many non-relevant emails.")
    else:
        feedback.append("No emails in folder.")

    # --- Criterion 4: Cross-folder Search (10 pts) ---
    # Did they find spam?
    if res.get("junk_source_preserved", 0) > 0:
        score += 10
        feedback.append("Evidence of Junk folder search found.")
    else:
        feedback.append("No emails from Junk preserved (did you search Junk?).")

    # --- Criterion 5-7: Certification Email (40 pts total) ---
    # Find best matching email
    emails = res.get("drafts", []) + res.get("sent", [])
    best_email = None
    
    for email in emails:
        if expected_recipient in email.get("to", ""):
            best_email = email
            break
    
    if best_email:
        score += 15
        feedback.append("Certification email drafted.")
        
        # Subject check (10 pts)
        subj = best_email.get("subject", "")
        if case_ref in subj:
            score += 10
            feedback.append("Case reference found in subject.")
        else:
            feedback.append(f"Case reference '{case_ref}' missing from subject.")
            
        # Body check (15 pts)
        body = best_email.get("body", "")
        body_score = 0
        # Mention of count
        import re
        if re.search(r'\b\d+\b', body):
            body_score += 5
        # Mention of keywords
        if any(k in body for k in ["license", "copyright", "patent", "gpl"]):
            body_score += 5
        # Mention of folders
        if "inbox" in body or "junk" in body or "spam" in body:
            body_score += 5
            
        score += body_score
        if body_score == 15:
            feedback.append("Certification body is complete.")
        else:
            feedback.append(f"Certification body incomplete (score: {body_score}/15).")
            
    else:
        feedback.append(f"No email found to {expected_recipient}.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }