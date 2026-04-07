#!/usr/bin/env python3
"""
Verifier for confidential_outreach_preparation task.

Checks:
1. `summit_nominees.txt` exists and contains 3 distinct email addresses.
2. A draft email exists addressed to `events@company.com`.
3. The draft has the 3 addresses from the file in the BCC field (Privacy check).
4. The draft does NOT have external addresses in TO or CC.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_emails(text):
    """Simple regex to extract email addresses from a string."""
    if not text:
        return []
    return re.findall(r'[\w.+-]+@[\w-]+\.[\w.-]+', text)

def verify_confidential_outreach(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Data from result
    file_exists = result.get("file_exists", False)
    file_content = result.get("file_content", "")
    draft = result.get("draft", {})
    draft_found = draft.get("found", False)
    
    # --- Criterion 1: Nominee File (25 pts) ---
    nominee_emails = set()
    if file_exists:
        extracted = extract_emails(file_content)
        # Normalize to lowercase
        nominee_emails = set(e.lower() for e in extracted)
        
        if len(nominee_emails) >= 3:
            score += 25
            feedback.append(f"Nominee file created with {len(nominee_emails)} emails.")
        elif len(nominee_emails) > 0:
            score += 10
            feedback.append(f"Nominee file has only {len(nominee_emails)} valid emails (expected 3).")
        else:
            feedback.append("Nominee file exists but contains no valid emails.")
    else:
        feedback.append("Nominee file not found.")

    # --- Criterion 2: Draft Creation & Recipient (25 pts) ---
    draft_to = [e.lower() for e in draft.get("to", [])]
    draft_subject = draft.get("subject", "")
    
    if draft_found:
        # Check To: events@company.com
        # Using flexible matching for email extraction from header strings like "Events <events@...>"
        to_addresses = []
        for t in draft_to:
            to_addresses.extend(extract_emails(t))
            
        if any("events@company.com" in addr for addr in to_addresses):
            score += 15
            feedback.append("Draft addressed correctly to events@company.com.")
        else:
            feedback.append(f"Draft found but TO field is incorrect: {draft_to}")
            
        # Check Subject keywords
        if "confidential" in draft_subject.lower() and "summit" in draft_subject.lower():
            score += 10
            feedback.append("Subject line is correct.")
        elif "confidential" in draft_subject.lower() or "summit" in draft_subject.lower():
            score += 5
            feedback.append("Subject line partially correct.")
    else:
        feedback.append("No draft email found.")

    # --- Criterion 3: Privacy/BCC Usage (50 pts) ---
    # This is the critical anti-gaming/security check
    if draft_found and len(nominee_emails) >= 3:
        draft_bcc = [e.lower() for e in draft.get("bcc", [])]
        draft_cc = [e.lower() for e in draft.get("cc", [])]
        
        # Extract pure emails from headers
        bcc_clean = set()
        for b in draft_bcc:
            bcc_clean.update(e.lower() for e in extract_emails(b))
            
        cc_clean = set()
        for c in draft_cc:
            cc_clean.update(e.lower() for e in extract_emails(c))
            
        # Check overlap: Are the nominees in BCC?
        matches_in_bcc = nominee_emails.intersection(bcc_clean)
        matches_in_cc = nominee_emails.intersection(cc_clean)
        matches_in_to = nominee_emails.intersection(set(extract_emails(str(draft_to))))
        
        if len(matches_in_bcc) >= 3:
            score += 30
            feedback.append("All nominees correctly placed in BCC.")
            
            # Bonus: Ensure they are NOT in To or Cc (Double-dipping check)
            if not matches_in_cc and not matches_in_to:
                score += 20
                feedback.append("Privacy preserved: Nominees not visible in To/Cc.")
            else:
                feedback.append("Privacy Warning: Nominees also appear in To/Cc!")
        elif len(matches_in_bcc) > 0:
            score += 10
            feedback.append(f"Only {len(matches_in_bcc)} nominees found in BCC.")
            if matches_in_cc or matches_in_to:
                 feedback.append("Privacy Failed: Nominees exposed in To/Cc.")
        else:
            if matches_in_cc or matches_in_to:
                feedback.append("Privacy Violation: Nominees exposed in To/Cc instead of BCC.")
            else:
                feedback.append("Nominees not found in draft recipients.")
                
    elif draft_found:
        feedback.append("Cannot verify BCC usage because nominee list is incomplete.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }