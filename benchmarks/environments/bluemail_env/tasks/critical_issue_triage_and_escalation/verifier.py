#!/usr/bin/env python3
"""
Verifier for critical_issue_triage_and_escalation task.

Scoring (100 pts total):
1. Triage Folder (40 pts):
   - Folder 'Triage-Critical' exists (20 pts)
   - Contains 3+ emails (20 pts) [Partial: 10 pts for 1-2]
   - (Implicit check: content relevance via keywords in verifier)
2. Escalation Workflow (60 pts):
   - Reply sent with "Issue acknowledged" (20 pts)
   - Forward sent to "escalation@techcorp.com" (20 pts)
   - Workflow Coherence: Reply and Forward are for the SAME thread (20 pts)

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_subject(subj):
    """Remove Re:, Fwd:, [List] prefixes to find base subject."""
    if not subj: return ""
    s = subj.lower()
    # Remove re:, fwd:, fw:
    s = re.sub(r'^\s*(re|fwd|fw):\s*', '', s)
    # Remove mailing list tags like [sadev]
    s = re.sub(r'\[.*?\]', '', s)
    return s.strip()

def verify_critical_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    CRITICAL_KEYWORDS = metadata.get('critical_keywords', ["panic", "fatal", "fail", "error"])
    ESCALATION_EMAIL = metadata.get('escalation_recipient', "escalation@techcorp.com").lower()

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

    # 1. Verify Triage Folder
    triage_exists = result.get('triage_folder_exists', False)
    triage_emails = result.get('triage_emails', [])
    triage_count = len(triage_emails)

    if triage_exists:
        score += 20
        feedback.append("Triage-Critical folder created.")
        
        # Check relevance
        relevant_count = 0
        for em in triage_emails:
            combined = (em.get('subject', '') + " " + em.get('body', '')).lower()
            if any(k in combined for k in CRITICAL_KEYWORDS):
                relevant_count += 1
        
        if triage_count >= 3:
            if relevant_count >= 2: # Allow some margin of error
                score += 20
                feedback.append(f"Folder populated with {triage_count} emails (mostly relevant).")
            else:
                score += 10
                feedback.append(f"Folder populated with {triage_count} emails, but content relevance is low.")
        elif triage_count > 0:
            score += 10
            feedback.append(f"Folder partially populated ({triage_count} emails).")
        else:
            feedback.append("Folder created but empty.")
    else:
        feedback.append("Triage-Critical folder NOT found.")

    # 2. Verify Escalation (Sent items)
    sent_emails = result.get('sent_emails', [])
    
    reply_found = False
    forward_found = False
    reply_subject_base = None
    forward_subject_base = None

    # Check for Reply
    for em in sent_emails:
        subj = em.get('subject', '').lower()
        body = em.get('body', '').lower()
        # Heuristic for reply: Subject has 're:', body has acknowledgement
        if 're:' in subj and 'acknowledged' in body:
            reply_found = True
            reply_subject_base = normalize_subject(subj)
            break
    
    if reply_found:
        score += 20
        feedback.append("Reply acknowledgement found.")
    else:
        feedback.append("No reply with 'Issue acknowledged' found.")

    # Check for Forward
    for em in sent_emails:
        subj = em.get('subject', '').lower()
        to_addr = em.get('to', '').lower()
        # Heuristic for forward: Subject has 'fwd'/'fw', sent to escalation
        if (('fwd:' in subj or 'fw:' in subj) or 'urgent' in em.get('body','').lower()) and ESCALATION_EMAIL in to_addr:
            forward_found = True
            forward_subject_base = normalize_subject(subj)
            break

    if forward_found:
        score += 20
        feedback.append(f"Forward to {ESCALATION_EMAIL} found.")
    else:
        feedback.append(f"No forward to {ESCALATION_EMAIL} found.")

    # 3. Verify Coherence (Same Thread)
    if reply_found and forward_found:
        # Check similarity of base subjects
        # Simple containment or exact match
        match = False
        if reply_subject_base and forward_subject_base:
            if reply_subject_base in forward_subject_base or forward_subject_base in reply_subject_base:
                match = True
            # Fuzzy match for short subjects or slight variations
            elif len(set(reply_subject_base.split()) & set(forward_subject_base.split())) >= 2:
                match = True
        
        if match:
            score += 20
            feedback.append("Workflow Coherence: Reply and Forward target the same thread.")
        else:
            feedback.append("Workflow Coherence Failed: Reply and Forward appear to be for different emails.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }