#!/usr/bin/env python3
"""
Verifier for reply_noise_filtering_and_report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reply_noise_filtering(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Replies-Archive' folder exists.
    2. Replies (Subject: Re:...) are in the archive (Precision).
    3. Inbox is free of replies (Recall).
    4. Remaining inbox emails are flagged (Important).
    5. Report email sent to manager contains the correct count of remaining inbox items.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from VM
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
    if result.get("archive_exists"):
        score += 10
        feedback.append("Folder 'Replies-Archive' created.")
    else:
        feedback.append("Folder 'Replies-Archive' NOT found.")

    # 2. Movement Logic (60 pts total)
    # Precision: Are the items in Archive actually replies?
    archive_count = result.get("archive_count", 0)
    archive_re_count = result.get("archive_re_count", 0)
    
    if archive_count > 0:
        precision = archive_re_count / archive_count
        if precision >= 0.9: # Allow slight margin for error
            score += 30
            feedback.append(f"Archive content correct ({archive_re_count}/{archive_count} are replies).")
        elif precision > 0.5:
            score += 15
            feedback.append(f"Archive content mixed ({archive_re_count}/{archive_count} are replies).")
        else:
            feedback.append(f"Archive contains mostly wrong items ({archive_re_count}/{archive_count} are replies).")
    else:
        feedback.append("Archive folder is empty.")

    # Recall: Did we get them all out of Inbox?
    inbox_count = result.get("inbox_count", 0)
    inbox_re_count = result.get("inbox_re_count", 0)
    
    # If items moved, check if inbox is clean
    if inbox_count > 0:
        if inbox_re_count == 0:
            score += 30
            feedback.append("Inbox clean (no replies remaining).")
        elif inbox_re_count < 3: # Allow 1-2 misses
            score += 20
            feedback.append(f"Inbox mostly clean ({inbox_re_count} replies remaining).")
        else:
            feedback.append(f"Inbox still cluttered ({inbox_re_count} replies remaining).")
    elif inbox_count == 0:
         # Empty inbox is technically "clean" of replies, but suspicious if everything was moved
         # We check if we moved non-replies to archive (Low Precision would catch this, but let's penalize here too if precision was bad)
         feedback.append("Inbox is empty.")
         if archive_count > 0 and (archive_re_count / archive_count) < 0.9:
             score += 0 # Moved everything, bad strategy
         else:
             score += 30 # Technically clean

    # 3. Flagging (15 pts)
    inbox_flagged = result.get("inbox_flagged_count", 0)
    # We expect all remaining inbox items to be flagged
    if inbox_count > 0:
        flag_ratio = inbox_flagged / inbox_count
        if flag_ratio >= 0.9:
            score += 15
            feedback.append("Remaining items flagged.")
        elif flag_ratio > 0.5:
            score += 7
            feedback.append(f"Some items flagged ({inbox_flagged}/{inbox_count}).")
        else:
            feedback.append(f"Items not flagged ({inbox_flagged}/{inbox_count}).")
    elif inbox_count == 0:
        # If inbox empty, nothing to flag. 
        # If they moved everything correctly (unlikely given task setup), they get points.
        # If they moved wrongly, they lost points in section 2.
        # We'll give points here to avoid double penalizing valid empty state logic.
        score += 15 

    # 4. Report (15 pts)
    report_found = result.get("report_found", False)
    reported_val = result.get("report_extracted_count")
    
    if report_found:
        feedback.append("Report email found.")
        # Check accuracy
        # Tolerance +/- 1
        if reported_val is not None and abs(reported_val - inbox_count) <= 1:
            score += 15
            feedback.append(f"Reported count correct (Reported: {reported_val}, Actual: {inbox_count}).")
        else:
            score += 5 # Found but wrong number
            feedback.append(f"Reported count incorrect (Reported: {reported_val}, Actual: {inbox_count}).")
    else:
        feedback.append("No report email found to manager@company.com.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }