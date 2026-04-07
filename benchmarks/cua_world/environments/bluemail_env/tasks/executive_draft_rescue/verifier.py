#!/usr/bin/env python3
"""
Verifier for executive_draft_rescue task.

Scoring Criteria:
1. Proposal Sent (30 pts): Email to client found in Sent.
2. Proposal Edited (30 pts): Body text contains specific added phrase.
3. Stale Draft Deleted (20 pts): 'Taco' draft not in Drafts.
4. Invoice Draft Kept (20 pts): 'Invoice' draft still in Drafts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_executive_draft_rescue(traj, env_info, task_info):
    """Verify the drafts were managed correctly."""
    
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('target_recipient', 'client.relations@strategic-partners.com')
    required_body_text = metadata.get('required_body_text', 'initial draft of the Q3 report for your review')
    stale_draft_subject = metadata.get('stale_draft_subject', 'Taco Tuesday?')
    preserved_draft_subject = metadata.get('preserved_draft_subject', 'Invoice #9928 Query')

    # 2. Retrieve result file
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

    # 3. Analyze Results
    score = 0
    feedback_parts = []
    
    sent_emails = result.get('sent_emails', [])
    draft_emails = result.get('draft_emails', [])

    # Check 1: Proposal Sent
    proposal_sent = False
    proposal_edited = False
    
    for email in sent_emails:
        if target_recipient in email.get('to', ''):
            proposal_sent = True
            body = email.get('body', '').lower()
            # Loose check for the required text (case insensitive, ignore extra whitespace)
            if required_body_text.lower() in body:
                proposal_edited = True
            break
            
    if proposal_sent:
        score += 30
        feedback_parts.append("Proposal email was sent.")
        if proposal_edited:
            score += 30
            feedback_parts.append("Proposal body was correctly edited.")
        else:
            feedback_parts.append("Proposal body was NOT edited correctly.")
    else:
        feedback_parts.append("Proposal email was NOT found in Sent items.")

    # Check 2: Stale Draft Deleted
    taco_found = False
    for email in draft_emails:
        if "taco" in email.get('subject', '').lower():
            taco_found = True
            break
            
    if not taco_found:
        score += 20
        feedback_parts.append("Stale 'Taco' draft deleted.")
    else:
        feedback_parts.append("Stale 'Taco' draft still exists.")

    # Check 3: Invoice Draft Preserved
    invoice_found = False
    for email in draft_emails:
        if "invoice" in email.get('subject', '').lower():
            invoice_found = True
            break
            
    if invoice_found:
        score += 20
        feedback_parts.append("Invoice draft preserved.")
    else:
        feedback_parts.append("Invoice draft was deleted (should have kept it).")

    # 4. Final Scoring
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }