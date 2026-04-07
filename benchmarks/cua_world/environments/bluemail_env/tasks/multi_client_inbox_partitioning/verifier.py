#!/usr/bin/env python3
"""
Verifier for multi_client_inbox_partitioning task.

Criteria:
1. Folder Hierarchy Created (15pts): .Clients.Apache and .Clients.ILUG exist.
2. Apache Sorted (15pts): At least 5 emails in Apache folder, correctly matched.
3. ILUG Sorted (15pts): At least 5 emails in ILUG folder, correctly matched.
4. Apache Priority (20pts): Emails in Apache folder are Flagged (Starred).
5. ILUG Deferral (20pts): Emails in ILUG folder are Unread.
6. Report Drafted (15pts): Draft exists to billing@ with correct subject.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_client_inbox_partitioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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

    # 1. Folder Hierarchy (15 pts)
    # Maildir typically represents nested folders as .Parent.Child
    apache_exists = result.get("apache_folder_exists", False)
    ilug_exists = result.get("ilug_folder_exists", False)
    
    if apache_exists and ilug_exists:
        score += 15
        feedback.append("Folder hierarchy 'Clients/Apache' and 'Clients/ILUG' created.")
    elif apache_exists or ilug_exists:
        score += 7
        feedback.append("Partial folder hierarchy created.")
    else:
        feedback.append("No required folders found.")

    # 2. Apache Sorting (15 pts)
    apache_count = result.get("apache_email_count", 0)
    apache_correct = result.get("apache_content_correct_count", 0)
    
    if apache_count >= 5 and apache_correct >= 3:
        score += 15
        feedback.append(f"Apache folder populated ({apache_count} emails).")
    elif apache_count > 0:
        score += 5
        feedback.append(f"Apache folder has {apache_count} emails (threshold 5).")

    # 3. ILUG Sorting (15 pts)
    ilug_count = result.get("ilug_email_count", 0)
    ilug_correct = result.get("ilug_content_correct_count", 0)
    
    if ilug_count >= 5 and ilug_correct >= 3:
        score += 15
        feedback.append(f"ILUG folder populated ({ilug_count} emails).")
    elif ilug_count > 0:
        score += 5
        feedback.append(f"ILUG folder has {ilug_count} emails (threshold 5).")

    # 4. Apache Priority - Flagged (20 pts)
    flagged_count = result.get("apache_flagged_count", 0)
    # Allow some margin of error, but mostly should be flagged
    if apache_count > 0 and flagged_count >= (apache_count - 1):
        score += 20
        feedback.append("Apache emails correctly Flagged/Starred.")
    elif flagged_count > 0:
        score += 5
        feedback.append(f"Only {flagged_count}/{apache_count} Apache emails flagged.")

    # 5. ILUG Deferral - Unread (20 pts)
    unread_count = result.get("ilug_unread_count", 0)
    if ilug_count > 0 and unread_count >= (ilug_count - 1):
        score += 20
        feedback.append("ILUG emails correctly marked as Unread.")
    elif unread_count > 0:
        score += 5
        feedback.append(f"Only {unread_count}/{ilug_count} ILUG emails marked unread.")

    # 6. Report Draft (15 pts)
    if result.get("report_draft_found", False):
        score += 15
        feedback.append("Triage report draft found.")
    else:
        feedback.append("No matching triage report draft found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }