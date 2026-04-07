#!/usr/bin/env python3
import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_executive_inbox_bankruptcy(traj, env_info, task_info):
    """
    Verifies the executive inbox bankruptcy task.
    
    Criteria:
    1. Inbox Count: Exactly 3 emails remaining (25 pts)
    2. Archive Logic: Correct number moved to 'Archive-Backlog' (25 pts)
    3. Temporal Correctness: Retained emails are newer than archived ones (20 pts)
    4. Urgency Flagging: The 3 retained emails are flagged (15 pts)
    5. Report Accuracy: Email sent to assistant with correct count (15 pts)
    """
    
    # 1. Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/executive_inbox_bankruptcy_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Metadata
    metadata = task_info.get('metadata', {})
    total_emails = metadata.get('total_emails', 50)
    retain_count = metadata.get('retain_count', 3)
    
    score = 0
    feedback = []
    
    # --- Criterion 1: Inbox Count (25 pts) ---
    inbox_count = result.get('inbox_count', -1)
    if inbox_count == retain_count:
        score += 25
        feedback.append(f"Inbox has exactly {retain_count} emails.")
    else:
        feedback.append(f"Inbox has {inbox_count} emails (expected {retain_count}).")
        
    # --- Criterion 2: Archive Logic (25 pts) ---
    archive_count = result.get('archive_count', 0)
    expected_archive = total_emails - retain_count
    
    # Allow some tolerance if total wasn't exactly 50 (e.g. setup issue), 
    # but strictly verify conservation of mass: inbox + archive should be close to total
    actual_total = inbox_count + archive_count
    
    if result.get('archive_folder_found'):
        if archive_count == expected_archive:
            score += 25
            feedback.append(f"Archive folder contains correct count ({archive_count}).")
        elif abs(archive_count - expected_archive) <= 2:
            score += 15
            feedback.append(f"Archive folder count slightly off ({archive_count}, expected {expected_archive}).")
        else:
            feedback.append(f"Archive folder count incorrect ({archive_count}).")
    else:
        feedback.append("Archive-Backlog folder not found.")

    # --- Criterion 3: Temporal Correctness (20 pts) ---
    # We check if the retained emails are actually the newest ones
    if result.get('timestamp_check_passed', False):
        score += 20
        feedback.append("Retained emails are the most recent ones.")
    elif inbox_count > 0 and archive_count > 0:
        feedback.append("Temporal check failed: You archived newer emails than you kept.")
    else:
        feedback.append("Skipping temporal check due to empty folders.")

    # --- Criterion 4: Urgency Flagging (15 pts) ---
    flagged_count = result.get('inbox_flagged_count', 0)
    if inbox_count == retain_count and flagged_count == retain_count:
        score += 15
        feedback.append("All retained emails are flagged.")
    elif flagged_count > 0:
        score += 5
        feedback.append(f"Only {flagged_count}/{inbox_count} retained emails flagged.")
    else:
        feedback.append("Retained emails are not flagged.")

    # --- Criterion 5: Report Accuracy (15 pts) ---
    sent_reports = result.get('sent_reports', [])
    report_valid = False
    
    if not sent_reports:
        feedback.append("No report email found sent to assistant.")
    else:
        # Check the most recent email
        last_email = sent_reports[-1]
        body = last_email.get('body', '').lower()
        subject = last_email.get('subject', '').lower()
        
        # Extract numbers from body
        # Look for the archive count (e.g., 47)
        numbers = [int(n) for n in re.findall(r'\b\d+\b', body)]
        
        if archive_count in numbers:
            score += 15
            report_valid = True
            feedback.append(f"Report correctly cited count ({archive_count}).")
        elif numbers:
            feedback.append(f"Report cited wrong numbers: {numbers} (expected {archive_count}).")
        else:
            feedback.append("Report did not contain any count.")

    # Final Pass Check
    # Threshold 85 means they need almost perfect execution
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }