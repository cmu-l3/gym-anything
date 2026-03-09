#!/usr/bin/env python3
"""
Verifier for false_positive_rescue task.

Scoring Breakdown:
1. False-Positives folder created: 15 pts
2. Legitimate emails rescued: 6 pts each (max 30 pts)
3. No spam rescued: 15 pts (flat)
   - Penalty: -5 pts per spam email in target folder (min 0)
4. Incident report drafted/sent: 25 pts
   - Must be to helpdesk-admin@techcorp.org
5. Report quality: 15 pts
   - Subject/body contains keywords AND number of emails found.

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_false_positive_rescue(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback = []

    # Criterion 1: Folder Creation (15 pts)
    if result.get("false_positives_folder_exists"):
        score += 15
        feedback.append("Folder 'False-Positives' created.")
    else:
        feedback.append("Failed to create 'False-Positives' folder.")

    # Criterion 2: Legitimate Emails Rescued (Max 30 pts)
    correct = result.get("correct_rescues", 0)
    score += (correct * 6)
    feedback.append(f"Rescued {correct}/5 legitimate emails.")

    # Criterion 3: Spam Avoidance (15 pts)
    spam_moved = result.get("spam_rescues", 0)
    spam_score = max(0, 15 - (spam_moved * 5))
    score += spam_score
    if spam_moved == 0:
        feedback.append("Perfect! No spam was accidentally moved.")
    else:
        feedback.append(f"Penalty: Moved {spam_moved} spam emails to rescue folder.")

    # Criterion 4 & 5: Incident Report (40 pts total)
    emails = result.get("emails_composed", [])
    report_found = False
    report_quality_score = 0
    
    for email in emails:
        to = email.get("to", "").lower()
        subject = email.get("subject", "").lower()
        body = email.get("body", "").lower()
        
        if "helpdesk-admin@techcorp.org" in to:
            report_found = True
            
            # Check Quality
            # Keywords: spam, filter, false positive, rescue, junk
            keywords = ["spam", "filter", "false", "positive", "junk", "legitimate", "rescue"]
            has_keywords = any(k in subject or k in body for k in keywords)
            
            # Numeric count check (digits)
            has_number = bool(re.search(r'\b\d+\b', subject + " " + body))
            
            if has_keywords and has_number:
                report_quality_score = 15
                feedback.append("Report quality: Excellent (keywords + count included).")
            elif has_keywords:
                report_quality_score = 8
                feedback.append("Report quality: Good (keywords included, missing specific count).")
            else:
                feedback.append("Report quality: Weak (missing keywords or count).")
            break
            
    if report_found:
        score += 25  # Base points for sending the email
        score += report_quality_score
        feedback.append("Incident report draft found.")
    else:
        feedback.append("No incident report to 'helpdesk-admin@techcorp.org' found.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }