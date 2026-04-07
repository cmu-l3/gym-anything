#!/usr/bin/env python3
"""
Verifier for build_failure_triage_and_report task.

Criteria:
1. 'Build-Alerts' folder created.
2. Contains emails with keywords (fail, error, bug, problem).
3. Emails in folder are marked Unread (anti-gaming: agent must change state).
4. Email forwarded to build-master with correct text.
5. Log file created with subjects.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_failure_triage(traj, env_info, task_info):
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
    
    keywords = ["fail", "error", "bug", "problem"]
    
    # 1. Folder Creation (10 pts)
    if result.get("folder_created"):
        score += 10
        feedback.append("Folder 'Build-Alerts' created.")
    else:
        feedback.append("Folder 'Build-Alerts' NOT found.")

    # 2. Triage Volume & Relevance (35 pts)
    # Target: 3+ emails, relevant keywords
    emails = result.get("emails", [])
    relevant_count = 0
    
    for email in emails:
        subj = email.get("subject", "").lower()
        if any(k in subj for k in keywords):
            relevant_count += 1
            
    if len(emails) >= 3:
        score += 20
        feedback.append(f"Folder populated with {len(emails)} emails.")
    elif len(emails) > 0:
        score += 10
        feedback.append(f"Folder partially populated ({len(emails)} emails).")
        
    if relevant_count >= 3:
        score += 15
        feedback.append(f"Emails are relevant ({relevant_count} match keywords).")
    elif relevant_count > 0:
        score += 5
        feedback.append("Some emails are relevant.")

    # 3. State Management (Unread) (15 pts)
    # We require the moved emails to be Unread.
    unread_count = result.get("unread_count", 0)
    if len(emails) > 0 and unread_count == len(emails):
        score += 15
        feedback.append("All archived emails marked Unread.")
    elif unread_count > 0:
        score += 5
        feedback.append(f"Some emails marked Unread ({unread_count}/{len(emails)}).")
    else:
        feedback.append("Emails NOT marked Unread.")

    # 4. Escalation (20 pts)
    esc = result.get("escalation_details")
    if esc:
        subj = esc.get("subject", "").lower()
        body = esc.get("body_snippet", "").lower()
        
        # Check recipient (already filtered in export script)
        recipient_ok = True 
        
        # Check forward indicator
        fwd_ok = "fw" in subj or "fwd" in subj
        
        # Check body text
        text_ok = "critical build failure" in body and "investigate" in body
        
        if recipient_ok and fwd_ok and text_ok:
            score += 20
            feedback.append("Escalation email sent correctly.")
        elif recipient_ok:
            score += 10
            feedback.append("Escalation email sent, but missing content or forward indicator.")
    else:
        feedback.append("No escalation email found in Sent items.")

    # 5. Logging (20 pts)
    if result.get("log_file_exists"):
        log_entries = result.get("log_entries", [])
        # Check if log entries match the subjects in the folder
        matches = 0
        folder_subjects = [e.get("subject", "").lower() for e in emails]
        
        for entry in log_entries:
            # loose matching
            if any(entry.lower() in s or s in entry.lower() for s in folder_subjects):
                matches += 1
        
        if matches >= 3:
            score += 20
            feedback.append("Log file accurately lists triage subjects.")
        elif matches > 0:
            score += 10
            feedback.append(f"Log file exists but only lists {matches} matching subjects.")
        else:
            score += 5
            feedback.append("Log file exists but content does not match folder subjects.")
    else:
        feedback.append("Log file NOT found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }