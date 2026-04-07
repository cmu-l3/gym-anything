#!/usr/bin/env python3
"""
Verifier for incident_triage_and_summary task.

Verifies:
1. Creation of Critical/Warning folders.
2. Correct categorization of emails based on keywords.
3. Sending of an acknowledgment reply.
4. Consistency between actual folder counts and the reported summary email.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_incident_triage(traj, env_info, task_info):
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

    # 1. Folder Creation (10 pts)
    folders = result.get("folders_found", [])
    has_critical = "Critical" in folders
    has_warning = "Warning" in folders
    
    if has_critical and has_warning:
        score += 10
        feedback.append("Both triage folders created.")
    elif has_critical or has_warning:
        score += 5
        feedback.append("One triage folder created.")
    else:
        feedback.append("No triage folders found.")

    # 2. Categorization Volume (20 pts)
    crit_count = result.get("critical_count", 0)
    warn_count = result.get("warning_count", 0)
    total_moved = crit_count + warn_count
    
    if total_moved >= 5:
        score += 20
        feedback.append(f"Categorized {total_moved} emails (Threshold: 5).")
    elif total_moved >= 1:
        score += 10
        feedback.append(f"Categorized {total_moved} emails (Threshold: 5).")
    else:
        feedback.append("No emails moved to triage folders.")

    # 3. Keyword Accuracy (20 pts)
    # We penalize if non-matching emails are moved
    crit_correct = result.get("critical_correct_keyword_count", 0)
    warn_correct = result.get("warning_correct_keyword_count", 0)
    
    # Calculate accuracy only if emails exist
    if crit_count > 0:
        crit_acc = crit_correct / crit_count
        if crit_acc == 1.0: score += 10
        elif crit_acc > 0.5: score += 5
    else:
        # If no emails, no points for accuracy, but we don't penalize double (already lost volume points)
        pass

    if warn_count > 0:
        warn_acc = warn_correct / warn_count
        if warn_acc == 1.0: score += 10
        elif warn_acc > 0.5: score += 5
    
    feedback.append(f"Keyword Accuracy - Critical: {crit_correct}/{crit_count}, Warning: {warn_correct}/{warn_count}.")

    # 4. Critical Reply (20 pts)
    if result.get("reply_found"):
        score += 20
        feedback.append("Acknowledgment reply found.")
    else:
        feedback.append("No acknowledgment reply detected containing 'investigating' and 'acknowledged'.")

    # 5. Report Exists (10 pts)
    if result.get("summary_found"):
        score += 10
        feedback.append("Handover report found.")
    else:
        feedback.append("No handover report to sre-leads@company.com found.")

    # 6. Data Consistency (20 pts)
    # Check if numbers in body match crit_count and warn_count
    summary_body = result.get("summary_body", "")
    consistency_passed = False
    
    if summary_body:
        # Extract numbers using regex
        # Pattern looks for "Critical Issues: 5" or "Critical: 5" etc
        # Flexible regex
        crit_match = re.search(r'critical.*?:?\s*(\d+)', summary_body, re.IGNORECASE)
        warn_match = re.search(r'warn.*?:?\s*(\d+)', summary_body, re.IGNORECASE)
        
        if crit_match and warn_match:
            reported_crit = int(crit_match.group(1))
            reported_warn = int(warn_match.group(1))
            
            if reported_crit == crit_count and reported_warn == warn_count:
                score += 20
                consistency_passed = True
                feedback.append(f"Reported counts ({reported_crit}, {reported_warn}) match actuals.")
            else:
                feedback.append(f"Data Mismatch: Reported ({reported_crit}, {reported_warn}) vs Actual ({crit_count}, {warn_count}).")
        else:
            feedback.append("Could not parse counts from summary email.")

    return {
        "passed": score >= 70 and consistency_passed,
        "score": score,
        "feedback": " ".join(feedback)
    }