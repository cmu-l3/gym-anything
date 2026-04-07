#!/usr/bin/env python3
"""
Verifier for mailbox_health_report task.

Scoring Criteria:
1. Report File Mechanics (15 pts): File exists, created during task, non-empty.
2. Data Accuracy (40 pts):
   - Folder counts in report match actual Maildir counts (+/- tolerance).
   - Top senders identified (regex match against known corpus senders).
3. Communication (35 pts):
   - Draft email exists to correct recipient.
   - Subject line contains keywords.
   - Body summarizes metrics.
4. Completeness (10 pts): Total count mentioned in report.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mailbox_health_report(traj, env_info, task_info):
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

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('count_tolerance', 10)
    
    score = 0
    feedback = []

    # --- 1. Report File Mechanics (15 pts) ---
    if result.get('report_exists') and result.get('report_created_during_task'):
        if result.get('report_size', 0) > 50:
            score += 15
            feedback.append("Report file created and has content.")
        else:
            score += 5
            feedback.append("Report file created but is very small.")
    else:
        feedback.append("Report file not found or not created during task.")
        # Critical failure if no report
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    report_text = result.get('report_content', '').lower()
    actual_counts = result.get('final_counts', {})

    # --- 2. Data Accuracy (40 pts) ---
    
    # Helper to find numbers associated with keywords
    def check_count_accuracy(keyword, actual_val, points):
        # Regex looks for keyword followed loosely by a number
        # e.g., "Inbox: 50" or "Inbox count 50" or "50 in Inbox"
        matches = re.findall(rf'{keyword}.*?(\d+)|(\d+).*?{keyword}', report_text)
        
        best_match_diff = float('inf')
        found_num = None
        
        for m in matches:
            # m is tuple ('50', '') or ('', '50')
            num_str = m[0] or m[1]
            if num_str:
                val = int(num_str)
                diff = abs(val - actual_val)
                if diff < best_match_diff:
                    best_match_diff = diff
                    found_num = val
        
        if found_num is not None and best_match_diff <= tolerance:
            return points, f"{keyword.title()} count accurate ({found_num} vs {actual_val})."
        elif found_num is not None:
            return points // 2, f"{keyword.title()} count inaccurate ({found_num} vs {actual_val})."
        else:
            return 0, f"{keyword.title()} count not found in report."

    # Check Inbox (20 pts)
    pts, msg = check_count_accuracy('inbox', actual_counts.get('inbox', 0), 20)
    score += pts
    feedback.append(msg)

    # Check Junk (10 pts)
    pts, msg = check_count_accuracy('junk', actual_counts.get('junk', 0), 10)
    score += pts
    feedback.append(msg)
    
    # Check Top Senders (10 pts)
    # Known corpus keywords
    known_senders = ['spamassassin', 'ilug', 'exmh', 'zzzzteana', 'razor', 'linux', 'sourceforge', 'paypal', 'admin']
    found_senders = [s for s in known_senders if s in report_text]
    if len(found_senders) >= 2:
        score += 10
        feedback.append(f"Senders identified: {', '.join(found_senders)}")
    elif len(found_senders) == 1:
        score += 5
        feedback.append(f"Only one sender identified: {found_senders[0]}")
    else:
        feedback.append("No distinct senders identified in report.")

    # --- 3. Communication / Email Draft (35 pts) ---
    found_emails = result.get('found_emails', [])
    valid_email = None
    
    for email_data in found_emails:
        if "ops-director@company.com" in email_data.get('to', '').lower():
            valid_email = email_data
            break
            
    if valid_email:
        score += 15
        feedback.append("Draft email found to correct recipient.")
        
        subj = valid_email.get('subject', '').lower()
        body = valid_email.get('body', '').lower()
        
        # Subject Relevance (10 pts)
        if any(w in subj for w in ['mailbox', 'health', 'report', 'audit', 'quarterly']):
            score += 10
            feedback.append("Subject line relevant.")
        else:
            feedback.append("Subject line missing keywords.")
            
        # Body Content (10 pts) - check for digits indicating metrics
        if re.search(r'\d+', body):
            score += 10
            feedback.append("Email body contains metrics.")
        else:
            feedback.append("Email body missing quantitative data.")
    else:
        feedback.append("No draft email found to ops-director@company.com.")

    # --- 4. Completeness (10 pts) ---
    # Check for total count
    if 'total' in report_text and re.search(r'total.*?(\d+)|(\d+).*?total', report_text):
        score += 10
        feedback.append("Total count included in report.")
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }