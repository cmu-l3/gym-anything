#!/usr/bin/env python3
"""
Verifier for content_classification_audit task.

Task: Classify emails into 'Security-Review' and 'General-Cleared' folders and send a report.

Scoring Criteria (100 points total):
1. Security-Review folder exists (10 pts)
2. Security-Review populated (15 pts: >7 emails, partial 5 pts >2)
3. General-Cleared folder exists (10 pts)
4. General-Cleared populated (15 pts: >11 emails, partial 5 pts >4)
5. Inbox substantially cleared (10 pts: <15 remaining)
6. Report email drafted/sent (20 pts)
7. Report quality (10 pts: contains counts)
8. Report context (10 pts: contains security keywords)

Pass threshold: 65/100
"""

import json
import os
import sys
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_content_classification_audit(traj, env_info, task_info):
    """Verify content classification audit task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    security_folder_name = metadata.get('security_folder', 'Security-Review').lower()
    general_folder_name = metadata.get('general_folder', 'General-Cleared').lower()
    report_recipient = metadata.get('report_recipient', 'ciso@company.org').lower()
    security_keywords = metadata.get('security_keywords', [])

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

    # 2. Extract Data
    custom_folders = {k.lower(): v for k, v in result.get('custom_folders', {}).items()}
    inbox_count = result.get('current_inbox_count', 50)
    outgoing_emails = result.get('outgoing_emails', [])
    
    score = 0
    feedback = []

    # 3. Evaluate Folders (50 pts total)
    
    # Security Folder (25 pts)
    security_exists = security_folder_name in custom_folders
    security_count = custom_folders.get(security_folder_name, 0)
    
    if security_exists:
        score += 10
        feedback.append(f"✓ Security folder created")
        
        if security_count >= 8:
            score += 15
            feedback.append(f"✓ Security folder populated ({security_count} emails)")
        elif security_count >= 3:
            score += 5
            feedback.append(f"⚠ Security folder partially populated ({security_count} emails)")
        else:
            feedback.append(f"✗ Security folder empty or nearly empty ({security_count} emails)")
    else:
        # Check for near matches (e.g., 'security', 'security-audit')
        partial_match = any('security' in k for k in custom_folders)
        if partial_match:
            feedback.append(f"✗ 'Security-Review' folder missing (found similar folder, check naming)")
        else:
            feedback.append(f"✗ 'Security-Review' folder missing")

    # General Folder (25 pts)
    general_exists = general_folder_name in custom_folders
    general_count = custom_folders.get(general_folder_name, 0)
    
    if general_exists:
        score += 10
        feedback.append(f"✓ General folder created")
        
        if general_count >= 12:
            score += 15
            feedback.append(f"✓ General folder populated ({general_count} emails)")
        elif general_count >= 5:
            score += 5
            feedback.append(f"⚠ General folder partially populated ({general_count} emails)")
        else:
            feedback.append(f"✗ General folder empty or nearly empty ({general_count} emails)")
    else:
        partial_match = any('general' in k for k in custom_folders)
        if partial_match:
            feedback.append(f"✗ 'General-Cleared' folder missing (found similar folder, check naming)")
        else:
            feedback.append(f"✗ 'General-Cleared' folder missing")

    # 4. Evaluate Inbox State (10 pts)
    if inbox_count < 15:
        score += 10
        feedback.append(f"✓ Inbox substantially cleared ({inbox_count} remaining)")
    elif inbox_count < 25:
        score += 5
        feedback.append(f"⚠ Inbox partially cleared ({inbox_count} remaining)")
    else:
        feedback.append(f"✗ Inbox not cleared ({inbox_count} remaining)")

    # 5. Evaluate Report (40 pts)
    # Find the best matching email
    report_email = None
    for email in outgoing_emails:
        if report_recipient in email.get('to', '').lower():
            report_email = email
            break
    
    if report_email:
        score += 20
        feedback.append(f"✓ Report email found to {report_recipient}")
        
        # Check for counts (regex for numbers)
        # Look for at least two distinct numbers in the body (e.g. "Security: 20", "General: 25")
        body = report_email.get('body', '')
        subject = report_email.get('subject', '')
        full_text = f"{subject} {body}"
        
        numbers = re.findall(r'\b\d+\b', body)
        # We expect at least 2 numbers (counts for 2 categories)
        if len(set(numbers)) >= 2:
            score += 10
            feedback.append(f"✓ Report includes numeric counts")
        else:
            feedback.append(f"✗ Report missing clear numeric counts")
            
        # Check for security keywords
        # We want to see terms describing what was found
        found_keywords = [kw for kw in security_keywords if kw in full_text]
        if len(found_keywords) >= 2:
            score += 10
            feedback.append(f"✓ Report includes context ({len(found_keywords)} keywords found)")
        else:
            feedback.append(f"✗ Report lacks descriptive security context")
    else:
        feedback.append(f"✗ No report email found addressed to {report_recipient}")

    # Final Check
    passed = score >= 65 and security_exists and general_exists and (report_email is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "custom_folders": custom_folders,
            "inbox_count": inbox_count,
            "report_found": report_email is not None
        }
    }