#!/usr/bin/env python3
"""
Verifier for execute_csv_mail_merge task.

Verification Strategy (Programmatic):
1. Timestamp & Output check: Was the Unsent Messages file created/modified during task? (10 pts)
2. Message Count: Exactly 15 emails generated? (20 pts)
3. Recipient Verification: Do the "To:" headers map exactly to the 15 vendors? (20 pts)
4. Subject Personalization: Dynamic subjects correct with no literal {{ tags? (25 pts)
5. Body Personalization: Dynamic body text correct with no literal {{ tags? (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mail_merge(traj, env_info, task_info):
    """
    Evaluate the parsed mbox JSON to determine if mail merge was successful.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_count', 15)
    vendors = metadata.get('vendors', [])

    # Retrieve output
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    file_exists = result.get("file_exists", False)
    file_mtime = result.get("file_mtime", 0)
    task_start = result.get("task_start", 0)
    emails = result.get("emails", [])
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Unsent Messages folder does not exist or is empty."}
        
    # Criterion 1: File Modification & Anti-Gaming (10 points)
    if file_mtime >= task_start:
        score += 10
        feedback_parts.append("Outbox modified during task timeframe.")
    else:
        feedback_parts.append("Outbox was not modified during the task. Possible gaming.")
        
    # Criterion 2: Message Count (20 points)
    actual_count = len(emails)
    if actual_count == expected_count:
        score += 20
        feedback_parts.append(f"Correct message count ({actual_count}).")
    elif actual_count > 0:
        partial_pts = int(20 * (actual_count / expected_count))
        score += partial_pts
        feedback_parts.append(f"Generated {actual_count}/{expected_count} messages (partial credit).")
    else:
        feedback_parts.append("No generated messages found in Outbox.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Map expected vendors for checking
    expected_emails = {v["Email"].lower(): v for v in vendors}
    
    matched_recipients = 0
    matched_subjects = 0
    matched_bodies = 0
    
    for em in emails:
        to_header = em.get("to", "").lower()
        subject = em.get("subject", "")
        body = em.get("body", "")
        
        # Check Recipient
        # Try to find which vendor this belongs to
        target_vendor = None
        for email_addr, vendor in expected_emails.items():
            if email_addr in to_header:
                target_vendor = vendor
                matched_recipients += 1
                break
                
        if not target_vendor:
            continue
            
        # Check Subject Personalization
        expected_subject = f"Account Update: {target_vendor['Company']}"
        if expected_subject in subject and "{{" not in subject and "}}" not in subject:
            matched_subjects += 1
            
        # Check Body Personalization
        expected_greeting = f"Dear {target_vendor['FirstName']},"
        expected_context = f"billing address for {target_vendor['Company']} in your records"
        if expected_greeting in body and expected_context in body and "{{" not in body and "}}" not in body:
            matched_bodies += 1

    # Criterion 3: Recipient Mapping (20 points)
    recip_score = int(20 * (matched_recipients / expected_count))
    score += recip_score
    if matched_recipients == expected_count:
        feedback_parts.append("All recipients accurately mapped.")
    else:
        feedback_parts.append(f"{matched_recipients} recipients mapped correctly.")
        
    # Criterion 4: Subject Personalization (25 points)
    subj_score = int(25 * (matched_subjects / expected_count))
    score += subj_score
    if matched_subjects == expected_count:
        feedback_parts.append("All subjects cleanly personalized.")
    else:
        feedback_parts.append(f"{matched_subjects} subjects personalized correctly.")
        
    # Criterion 5: Body Personalization (25 points)
    body_score = int(25 * (matched_bodies / expected_count))
    score += body_score
    if matched_bodies == expected_count:
        feedback_parts.append("All message bodies cleanly personalized.")
    else:
        feedback_parts.append(f"{matched_bodies} message bodies personalized correctly.")

    # Threshold: Pass if at least 75 points and Count/Subject are mostly met
    passed = score >= 75 and actual_count == expected_count and matched_subjects >= expected_count - 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }