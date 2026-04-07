#!/usr/bin/env python3
"""
Verifier for meeting_followup_drafts task.

Scoring Criteria (100 points total):
1. Organization (25 pts):
   - 'Meridian-Q4' folder exists (10 pts)
   - Folder contains 5+ emails (10 pts)
   - Inbox reduced by 5+ emails (5 pts)

2. Draft 1 - Client Thank You (25 pts):
   - Correct Recipient (10 pts)
   - Subject keywords (5 pts)
   - Body keywords 'thank you' + 'meeting' (10 pts)

3. Draft 2 - Internal Action Items (25 pts):
   - Correct Recipient (10 pts)
   - Subject keywords (5 pts)
   - Body has 3+ bullet points (10 pts)

4. Draft 3 - Manager Summary (25 pts):
   - Correct Recipient (10 pts)
   - Subject keywords (5 pts)
   - Body keywords 'Meridian' + 'next step' (10 pts)

Pass Threshold: 65 points.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_draft_match(draft, criteria):
    """
    Check if a draft matches specific criteria.
    Returns score and feedback list.
    """
    score = 0
    feedback = []
    
    # Check Recipient (Partial match allowed for names, but email must be present)
    if criteria['to'].lower() in draft.get('to', '').lower():
        score += 10
        feedback.append(f"Recipient correct ({criteria['to']})")
    else:
        feedback.append(f"Recipient mismatch: Found '{draft.get('to')}', expected '{criteria['to']}'")
        return 0, feedback  # If wrong recipient, likely wrong draft entirely

    # Check Subject
    subj = draft.get('subject', '').lower()
    subj_hits = [kw for kw in criteria['subject_keywords'] if kw.lower() in subj]
    if len(subj_hits) >= 1:
        score += 5
        feedback.append("Subject keywords matched")
    else:
        feedback.append(f"Subject missing keywords: {criteria['subject_keywords']}")

    # Check Body
    body = draft.get('body', '').lower()
    
    if 'body_requirements' in criteria:
        # Check for bullet points (lines starting with -, *, or digit.)
        bullets = re.findall(r'^\s*[-*•\d][.)]?\s+.+$', body, re.MULTILINE)
        if len(bullets) >= 3:
            score += 10
            feedback.append(f"Body has {len(bullets)} action items")
        else:
            feedback.append(f"Body missing action list (found {len(bullets)}, need 3+)")
            
    if 'body_keywords' in criteria:
        body_hits = [kw for kw in criteria['body_keywords'] if kw.lower() in body]
        if len(body_hits) == len(criteria['body_keywords']):
            score += 10
            feedback.append("Body content verified")
        else:
            feedback.append(f"Body missing keywords: {criteria['body_keywords']}")

    return score, feedback

def verify_meeting_followup_drafts(traj, env_info, task_info):
    """Verify meeting followup drafts task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback_all = []
    
    # =========================================================
    # 1. Verify Organization (25 points)
    # =========================================================
    folder_exists = result.get('folder_exists', False)
    folder_count = result.get('folder_email_count', 0)
    inbox_count = result.get('current_inbox_count', 50)
    
    # Baseline inbox is 50. If 5 moved, expected <= 45.
    inbox_reduced = inbox_count <= 45
    
    if folder_exists:
        score += 10
        feedback_all.append("Folder 'Meridian-Q4' created")
    else:
        feedback_all.append("Folder 'Meridian-Q4' NOT found")
        
    if folder_count >= 5:
        score += 10
        feedback_all.append(f"Folder populated ({folder_count} emails)")
    elif folder_count > 0:
        score += 5
        feedback_all.append(f"Folder partially populated ({folder_count} emails)")
        
    if inbox_reduced:
        score += 5
        feedback_all.append("Inbox count reduced")
    
    # =========================================================
    # 2. Verify Drafts (75 points total)
    # =========================================================
    drafts = result.get('drafts', [])
    sent = result.get('sent_emails', [])
    
    # If agent sent them instead of saving as draft, we accept but penalize slightly?
    # Task says "Save as draft". Let's allow sent but maybe with a note, 
    # or just treat them as drafts for scoring purposes but strictly they should be drafts.
    # We will pool them but prioritize drafts.
    
    # Actually, let's treat sent emails as drafts for content verification 
    # but deduct points if they were sent? 
    # For simplicity in this implementation, we'll verify content regardless of draft/sent status
    # but the task description explicitly said "do NOT send".
    # We will check if they are in the drafts list first.
    
    all_messages = drafts + sent
    
    # Define criteria
    criteria_list = [
        {
            "name": "Client Thank-You",
            "to": "j.chen@meridian-corp.com",
            "subject_keywords": ["Thank You", "Q4", "Planning"],
            "body_keywords": ["thank you", "meeting"]
        },
        {
            "name": "Internal Action Items",
            "to": "engineering@mycompany.com",
            "subject_keywords": ["Action Items", "Meridian"],
            "body_requirements": "3+ bullets"
        },
        {
            "name": "Manager Summary",
            "to": "director@mycompany.com",
            "subject_keywords": ["Meeting Summary", "Meridian"],
            "body_keywords": ["meridian", "next step"]
        }
    ]
    
    matched_indices = set()
    
    for crit in criteria_list:
        best_score = 0
        best_fb = []
        best_idx = -1
        
        for idx, msg in enumerate(all_messages):
            if idx in matched_indices:
                continue
            
            # Check if this message is a candidate for this criteria based on TO address
            if crit['to'].lower() in msg.get('to', '').lower():
                s, fb = check_draft_match(msg, crit)
                
                # Check if it was sent (penalize 5 points per email if sent instead of draft)
                if msg in sent:
                    s = max(0, s - 5)
                    fb.append("PENALTY: Email was sent instead of saved as draft")
                
                if s > best_score:
                    best_score = s
                    best_fb = fb
                    best_idx = idx
        
        if best_idx != -1:
            matched_indices.add(best_idx)
            score += best_score
            feedback_all.append(f"Draft '{crit['name']}': {best_score}pts - " + ", ".join(best_fb))
        else:
            feedback_all.append(f"Draft '{crit['name']}': Not found")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_all)
    }