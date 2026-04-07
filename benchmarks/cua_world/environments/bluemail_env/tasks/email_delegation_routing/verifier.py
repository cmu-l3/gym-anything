#!/usr/bin/env python3
"""
Verifier for email_delegation_routing task.

Criteria:
1. Security Forwards (15 pts): >=2 emails to security-team@techcorp.org
2. Security Content (10 pts): Content contains security keywords
3. Dev Forwards (15 pts): >=2 emails to dev-team@techcorp.org
4. Dev Content (10 pts): Content contains dev keywords
5. Community Forwards (10 pts): >=1 email to community-lead@techcorp.org
6. Handoff Summary (20 pts): Email to director@techcorp.org
7. Summary Quality (15 pts): Subject/Body keywords
8. Inbox Preservation (5 pts): Inbox count >= 45 (originals forwarded, not moved)

Pass Threshold: 60 points
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_relevance(email_body, keywords):
    """Check if email body contains at least one keyword."""
    return any(k in email_body for k in keywords)

def verify_email_delegation_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    recipients = metadata.get('recipients', {})
    keywords = metadata.get('keywords', {})
    
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

    all_emails = result.get('sent_emails', []) + result.get('draft_emails', [])
    final_inbox_count = result.get('final_inbox_count', 0)
    
    score = 0
    feedback = []

    # Helper to find emails by recipient
    def find_emails_to(recipient):
        return [e for e in all_emails if recipient in e['to']]

    # 1. Security Forwards (15 pts + 10 pts relevance)
    sec_emails = find_emails_to(recipients.get('security', 'security-team'))
    if len(sec_emails) >= 2:
        score += 15
        feedback.append(f"Security forwards: {len(sec_emails)} (Pass)")
    elif len(sec_emails) == 1:
        score += 8
        feedback.append(f"Security forwards: 1 (Partial)")
    else:
        feedback.append(f"Security forwards: 0 (Fail)")

    # Check relevance
    sec_relevant = sum(1 for e in sec_emails if check_relevance(e['body'], keywords.get('security', [])))
    if sec_relevant >= 2:
        score += 10
        feedback.append("Security content: Relevant")
    elif sec_relevant == 1:
        score += 5
        feedback.append("Security content: Partially relevant")

    # 2. Dev Forwards (15 pts + 10 pts relevance)
    dev_emails = find_emails_to(recipients.get('dev', 'dev-team'))
    if len(dev_emails) >= 2:
        score += 15
        feedback.append(f"Dev forwards: {len(dev_emails)} (Pass)")
    elif len(dev_emails) == 1:
        score += 8
        feedback.append(f"Dev forwards: 1 (Partial)")
    else:
        feedback.append(f"Dev forwards: 0 (Fail)")

    dev_relevant = sum(1 for e in dev_emails if check_relevance(e['body'], keywords.get('dev', [])))
    if dev_relevant >= 2:
        score += 10
        feedback.append("Dev content: Relevant")
    elif dev_relevant == 1:
        score += 5
        feedback.append("Dev content: Partially relevant")

    # 3. Community Forwards (10 pts)
    comm_emails = find_emails_to(recipients.get('community', 'community-lead'))
    if len(comm_emails) >= 1:
        # Check relevance implicit in point award for this simpler category
        is_relevant = any(check_relevance(e['body'], keywords.get('community', [])) for e in comm_emails)
        if is_relevant:
            score += 10
            feedback.append("Community forward: Found and relevant")
        else:
            score += 5
            feedback.append("Community forward: Found but content mismatch")
    else:
        feedback.append("Community forward: None")

    # 4. Handoff Summary (20 pts + 5 pts subject + 10 pts body)
    dir_emails = find_emails_to(recipients.get('director', 'director@'))
    if dir_emails:
        score += 20
        feedback.append("Summary email found")
        
        summary = dir_emails[0]
        # Subject check
        subj_kw = ['handoff', 'delegation', 'routing', 'summary', 'report']
        if any(k in summary['subject'].lower() for k in subj_kw):
            score += 5
            feedback.append("Summary subject: Good")
            
        # Body check (mentions teams)
        body = summary['body']
        mentions = 0
        if 'security' in body: mentions += 1
        if 'dev' in body: mentions += 1
        if 'community' in body or 'linux' in body: mentions += 1
        
        if mentions >= 2:
            score += 10
            feedback.append("Summary body: Detailed")
        elif mentions == 1:
            score += 5
            feedback.append("Summary body: Minimal")
    else:
        feedback.append("Summary email missing")

    # 5. Inbox Preservation (5 pts)
    # Start was 50. Forwarding shouldn't delete. Moving would.
    if final_inbox_count >= 45:
        score += 5
        feedback.append("Inbox integrity preserved")
    else:
        feedback.append(f"Inbox depleted ({final_inbox_count} remaining) - user moved instead of forwarded?")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }