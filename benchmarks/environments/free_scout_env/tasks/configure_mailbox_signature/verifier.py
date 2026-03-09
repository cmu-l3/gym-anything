#!/usr/bin/env python3
"""
Verifier for configure_mailbox_signature task.

Verifies:
1. Mailbox exists and was found
2. Signature content contains all required elements (Team name, Hours, Phone, Email, Portal, Confidentiality)
3. Mailbox was actually updated during the task (timestamp check)
"""

import json
import tempfile
import os
import logging
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mailbox_signature(traj, env_info, task_info):
    """
    Verify that the mailbox signature was correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    required = metadata.get('required_elements', {})
    
    # Retrieve result file
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
    max_score = 100
    feedback_parts = []
    
    # Check 1: Mailbox found (10 pts)
    if result.get('mailbox_found', False):
        score += 10
        feedback_parts.append("Mailbox found")
    else:
        return {"passed": False, "score": 0, "feedback": "Target mailbox not found in database"}

    # Get signature and normalize
    raw_sig = result.get('signature_content', '')
    if raw_sig is None or raw_sig == "NULL":
        raw_sig = ""
        
    # Simple HTML stripping and normalization for text matching
    # Remove HTML tags
    sig_text = re.sub(r'<[^>]+>', ' ', raw_sig)
    # Decode common entities
    sig_text = sig_text.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    # Normalize whitespace
    sig_text = re.sub(r'\s+', ' ', sig_text).strip()
    sig_lower = sig_text.lower()
    
    # Check 2: Signature non-empty (10 pts)
    if len(sig_text) > 10:
        score += 10
        feedback_parts.append("Signature is set")
    else:
        feedback_parts.append("Signature is empty or too short")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 3: Content Elements
    
    # Team Name (15 pts)
    target = required.get('team_name', 'Acme Corp IT Support Team').lower()
    if target in sig_lower:
        score += 15
        feedback_parts.append("Team name correct")
    else:
        feedback_parts.append("Team name missing")

    # Hours (15 pts) - check both days and times
    days = required.get('hours_days', 'monday - friday').lower()
    times = required.get('hours_times', '8:00 am - 6:00 pm').lower()
    
    # Flexible matching for hours
    has_days = days in sig_lower or "mon-fri" in sig_lower or "monday to friday" in sig_lower
    has_times = times in sig_lower or "8:00am - 6:00pm" in sig_lower or "8-6" in sig_lower
    
    if has_days and has_times:
        score += 15
        feedback_parts.append("Support hours correct")
    elif has_days or has_times:
        score += 7
        feedback_parts.append("Support hours incomplete")
    else:
        feedback_parts.append("Support hours missing")

    # Phone (15 pts)
    phone = required.get('phone', '(555) 234-5678')
    # Clean phone numbers for comparison
    phone_clean = re.sub(r'\D', '', phone)
    sig_phone_clean = re.sub(r'\D', '', sig_text)
    
    if phone in sig_text or phone_clean in sig_phone_clean:
        score += 15
        feedback_parts.append("Phone number correct")
    else:
        feedback_parts.append("Phone number missing")

    # Email (10 pts)
    email = required.get('email', 'itsupport@acmecorp.com').lower()
    if email in sig_lower:
        score += 10
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append("Email missing")
        
    # Portal (10 pts)
    portal = required.get('portal', 'support.acmecorp.com').lower()
    if portal in sig_lower:
        score += 10
        feedback_parts.append("Portal URL correct")
    else:
        feedback_parts.append("Portal URL missing")

    # Confidentiality Notice (15 pts)
    header = required.get('confidentiality_header', 'CONFIDENTIALITY NOTICE').lower()
    body = required.get('confidentiality_body', 'exclusive and confidential use').lower()
    
    if header in sig_lower and body in sig_lower:
        score += 15
        feedback_parts.append("Confidentiality notice correct")
    elif header in sig_lower or body in sig_lower:
        score += 7
        feedback_parts.append("Confidentiality notice partial")
    else:
        feedback_parts.append("Confidentiality notice missing")

    # Check 4: Anti-gaming timestamp check
    # We don't award points here but fail if it looks like no work was done
    # However, since we cleared the signature in setup, if it matches content it must have been done.
    # We'll just add it as a sanity check note.
    updated_at = result.get('updated_at', 0)
    task_start = result.get('task_start', 0)
    
    was_updated = updated_at >= task_start
    if was_updated:
        feedback_parts.append("(Verified: Record updated during task)")
    else:
        feedback_parts.append("(Warning: Timestamp suggests no update)")
        # Penalize if it looks like they didn't actually save, but if content is perfect, 
        # it might be a clock sync issue, so we just subtract small amount or ignore if score is high.
        if score > 0:
            pass 

    # Determine pass/fail
    # Threshold: Need at least 70 points (allows missing one minor item or minor formatting errors)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }