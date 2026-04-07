#!/usr/bin/env python3
"""
Verifier for duplicate_detection_cleanup task.

Scoring Criteria:
1. Inbox Reduced (25 pts): Count decreased by the number of duplicates (~8).
2. No Originals Lost (20 pts): All 25 unique subjects are still present.
3. Trash Increased (15 pts): Trash contains the removed duplicates.
4. Report Drafted (25 pts): Email to it-infrastructure@company.com exists.
5. Report Quality (15 pts): Subject/body contains keywords and numbers.

Anti-gaming:
- Bulk delete penalty: If inbox < 15, max score is capped.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_subject(subj):
    """Normalize subject string for comparison (ignore case, whitespace)."""
    if not subj: return ""
    return re.sub(r'\s+', ' ', subj.strip().lower())

def verify_duplicate_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('report_recipient', 'it-infrastructure@company.com')
    initial_total = metadata.get('initial_total_count', 33)
    
    # Copy result file
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
    feedback_parts = []
    
    # Data from export
    inbox_count = result.get('inbox_count', 0)
    trash_count = result.get('trash_count', 0)
    inbox_subjects = [normalize_subject(s) for s in result.get('inbox_subjects', [])]
    trash_subjects = [normalize_subject(s) for s in result.get('trash_subjects', [])]
    outgoing = result.get('outgoing_emails', [])
    
    unique_gt = [normalize_subject(s) for s in result.get('unique_subjects_ground_truth', [])]
    duplicate_gt = [normalize_subject(s) for s in result.get('duplicated_subjects_ground_truth', [])]
    
    # Anti-Gaming: Bulk Deletion Check
    # If the agent just deleted everything, they might technically "remove duplicates"
    # but fail the core objective.
    if inbox_count < 15:
        feedback_parts.append("PENALTY: Inbox count dangerously low (<15). Suspected bulk deletion.")
        # We will continue scoring, but the 'No Originals Lost' check will punish this severely.

    # CRITERION 1: Inbox Reduced (25 pts)
    # Target: 33 -> 25 (reduction of 8)
    reduction = initial_total - inbox_count
    if 24 <= inbox_count <= 26:
        score += 25
        feedback_parts.append(f"Inbox count perfect ({inbox_count})")
    elif 27 <= inbox_count <= 29:
        score += 15
        feedback_parts.append(f"Inbox count good ({inbox_count}), some duplicates remain")
    elif inbox_count < 24:
        # Too many deleted (unless they are originals, checked later)
        if inbox_count > 15: 
             score += 15
             feedback_parts.append(f"Inbox count ({inbox_count}) suggests extra deletions")
        else:
             feedback_parts.append(f"Inbox count ({inbox_count}) too low")
    else:
        feedback_parts.append(f"Inbox count high ({inbox_count}), duplicates likely remaining")

    # CRITERION 2: No Originals Lost (20 pts)
    # Check if all unique subjects from ground truth exist in current inbox
    missing_originals = 0
    for subj in unique_gt:
        if subj not in inbox_subjects:
            missing_originals += 1
            
    if missing_originals == 0:
        score += 20
        feedback_parts.append("All unique emails preserved")
    elif missing_originals <= 2:
        score += 12
        feedback_parts.append(f"Most unique emails preserved ({missing_originals} missing)")
    else:
        feedback_parts.append(f"Failed to preserve originals ({missing_originals} missing)")

    # CRITERION 3: Trash Increased/Contains Duplicates (15 pts)
    # Check if duplicate subjects are in trash
    duplicates_in_trash = 0
    for subj in duplicate_gt:
        if subj in trash_subjects:
            duplicates_in_trash += 1
    
    # Note: A subject might appear in trash multiple times if they deleted the original too.
    # We just check if *at least one* instance of the duplicate subject is in trash.
    if duplicates_in_trash >= 6:
        score += 15
        feedback_parts.append("Duplicates confirmed in Trash")
    elif duplicates_in_trash >= 3:
        score += 8
        feedback_parts.append("Some duplicates found in Trash")
    else:
        feedback_parts.append("Few/No duplicates found in Trash")

    # CRITERION 4: Incident Report Drafted (25 pts)
    report_found = False
    report_email = None
    
    for email in outgoing:
        to_field = email.get('to', '').lower()
        if expected_recipient.lower() in to_field:
            report_found = True
            report_email = email
            break
            
    if report_found:
        score += 25
        feedback_parts.append("Incident report drafted/sent")
    else:
        feedback_parts.append("No report found to 'it-infrastructure@company.com'")

    # CRITERION 5: Report Quality (15 pts)
    # Check for keywords: duplicate, sync, cleanup, incident
    # Check for number digit
    if report_found and report_email:
        content = (report_email.get('subject', '') + " " + report_email.get('body', '')).lower()
        
        keywords = ['duplicate', 'sync', 'clean', 'incident', 'dedup', 'copy', 'copies']
        has_keyword = any(k in content for k in keywords)
        has_number = bool(re.search(r'\d+', content))
        
        if has_keyword and has_number:
            score += 15
            feedback_parts.append("Report content valid (keywords + count)")
        elif has_keyword:
            score += 8
            feedback_parts.append("Report content partial (keywords only)")
        else:
            feedback_parts.append("Report content missing key details")
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }