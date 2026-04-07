#!/usr/bin/env python3
"""
Verifier for release_feedback_synthesis task.

Scoring Breakdown:
1. Relevance Flagging (30 pts): 3+ emails flagged containing keywords.
2. Draft Creation (20 pts): Draft exists to correct recipient.
3. Draft Subject (10 pts): Subject contains "Release" and "Feedback".
4. Content Synthesis (40 pts): Draft body contains Subject lines of flagged emails.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_release_feedback_synthesis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_keywords = [k.lower() for k in metadata.get('target_keywords', ["release", "version", "v2", "announce"])]
    expected_recipient = metadata.get('recipient', "product-team@company.com")
    
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

    analysis = result.get('analysis', {})
    flagged_emails = analysis.get('flagged_emails', [])
    drafts = analysis.get('drafts', [])
    
    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # 1. Relevance Flagging (30 pts)
    # ----------------------------------------------------------------
    relevant_flagged = 0
    flagged_subjects = []
    
    for email in flagged_emails:
        subj = email.get('subject', '').lower()
        body = email.get('body', '').lower()
        flagged_subjects.append(email.get('subject', '')) # Keep original case for later check
        
        # Check if email is relevant
        if any(k in subj for k in target_keywords) or any(k in body for k in target_keywords):
            relevant_flagged += 1

    if relevant_flagged >= 3:
        score += 30
        feedback.append(f"Success: Flagged {relevant_flagged} relevant emails.")
    elif relevant_flagged > 0:
        partial = relevant_flagged * 10
        score += partial
        feedback.append(f"Partial: Flagged {relevant_flagged} relevant emails (target: 3).")
    else:
        feedback.append("Fail: No relevant emails were flagged.")

    # ----------------------------------------------------------------
    # 2. Draft Creation (20 pts)
    # ----------------------------------------------------------------
    target_draft = None
    
    # Find the best matching draft
    for d in drafts:
        if expected_recipient.lower() in d.get('to', '').lower():
            target_draft = d
            break
    
    # If no exact match, look for any draft created during task
    if not target_draft and drafts:
        target_draft = drafts[0]
        feedback.append("Warning: Draft recipient does not match exactly, checking content anyway.")

    if target_draft:
        if expected_recipient.lower() in target_draft.get('to', '').lower():
            score += 20
            feedback.append("Success: Draft created with correct recipient.")
        else:
            score += 10 # Partial credit for creating a draft at all
            feedback.append(f"Partial: Draft created but wrong recipient ('{target_draft.get('to')}').")
    else:
        feedback.append("Fail: No draft created.")
        # Stop here if no draft
        return {
            "passed": False,
            "score": score,
            "feedback": " ".join(feedback)
        }

    # ----------------------------------------------------------------
    # 3. Draft Subject (10 pts)
    # ----------------------------------------------------------------
    d_subj = target_draft.get('subject', '').lower()
    if "release" in d_subj and "feedback" in d_subj:
        score += 10
        feedback.append("Success: Draft subject is correct.")
    elif "release" in d_subj or "feedback" in d_subj:
        score += 5
        feedback.append("Partial: Draft subject contains some keywords.")
    else:
        feedback.append("Fail: Draft subject missing keywords.")

    # ----------------------------------------------------------------
    # 4. Content Synthesis (40 pts)
    # ----------------------------------------------------------------
    # Check if flagged subjects appear in the draft body
    d_body = target_draft.get('body', '').lower()
    matches = 0
    
    for fs in flagged_subjects:
        # Normalize: remove special chars, maybe just look for core distinct words?
        # Robust approach: Check if the full subject string (ignoring case) is in body
        if fs.strip().lower() in d_body:
            matches += 1
        else:
            # Fallback: Check for significant substring overlap (e.g. if subject was truncated)
            # If 80% of words in subject appear in body
            words = fs.lower().split()
            if len(words) > 3:
                found_words = sum(1 for w in words if w in d_body)
                if found_words / len(words) > 0.8:
                    matches += 1

    # Cap matches at 3 for full points
    matches_capped = min(matches, 3)
    
    if matches_capped >= 3:
        score += 40
        feedback.append("Success: Draft contains 3+ flagged subjects.")
    elif matches_capped > 0:
        pts = int((matches_capped / 3) * 40)
        score += pts
        feedback.append(f"Partial: Draft contains {matches_capped} flagged subjects.")
    else:
        feedback.append("Fail: Draft body does not contain flagged subjects.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }