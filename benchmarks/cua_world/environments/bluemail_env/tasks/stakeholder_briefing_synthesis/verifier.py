#!/usr/bin/env python3
"""
Verifier for stakeholder_briefing_synthesis task.

Scoring Criteria:
1. Engineering Email (15 pts): To 'engineering-lead@techcorp.com'
2. Infrastructure Email (15 pts): To 'infrastructure-lead@techcorp.com'
3. Compliance Email (15 pts): To 'compliance-officer@techcorp.com'
4. Subject Lines (10 pts): Must contain "Briefing", "Report", etc.
5. Content Relevance (15 pts): 5 pts per email for relevant keywords
6. Body Substance (10 pts): Emails are not empty/trivial
7. Master File (20 pts): Exists, non-trivial, multi-section

Pass Threshold: 65/100
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stakeholder_briefing(traj, env_info, task_info):
    """Verify stakeholder briefing task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    recipients = metadata.get('recipients', {})
    subject_keywords = metadata.get('required_subject_keywords', [])
    content_keywords = metadata.get('keywords', {})

    # Copy result
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
    feedback_parts = []
    
    all_emails = result.get('all_outgoing', [])
    briefing_file = result.get('briefing_file', {})

    # Helper to check email properties
    def check_email_for_role(role_key, target_email):
        best_match = None
        best_score = 0
        
        for email in all_emails:
            # Check To: (fuzzy match to account for "Name <email>")
            if target_email.lower() not in email.get('to', '').lower():
                continue
            
            current_email_score = 0
            
            # Check created during task (anti-gaming)
            if not email.get('created_during_task', True):
                continue

            # 1. Base score for existence
            current_email_score += 15
            
            # 2. Subject Check
            subj = email.get('subject', '').lower()
            if any(k in subj for k in subject_keywords):
                current_email_score += 3.33  # 10 pts total / 3 emails
            
            # 3. Content Check
            body = email.get('body', '').lower()
            role_keywords = content_keywords.get(role_key, [])
            hits = sum(1 for k in role_keywords if k in body)
            if hits >= 2:
                current_email_score += 5
            
            # 4. Substance Check
            if len(body) > 100:
                current_email_score += 3.33 # 10 pts total / 3 emails

            if current_email_score > best_score:
                best_score = current_email_score
                best_match = email
        
        return best_score, best_match

    # Verify Engineering Email
    eng_score, eng_email = check_email_for_role('engineering', recipients['engineering'])
    score += eng_score
    if eng_email:
        feedback_parts.append(f"Engineering email found ({int(eng_score)} pts)")
    else:
        feedback_parts.append("Engineering email missing")

    # Verify Infrastructure Email
    infra_score, infra_email = check_email_for_role('infrastructure', recipients['infrastructure'])
    score += infra_score
    if infra_email:
        feedback_parts.append(f"Infrastructure email found ({int(infra_score)} pts)")
    else:
        feedback_parts.append("Infrastructure email missing")

    # Verify Compliance Email
    comp_score, comp_email = check_email_for_role('compliance', recipients['compliance'])
    score += comp_score
    if comp_email:
        feedback_parts.append(f"Compliance email found ({int(comp_score)} pts)")
    else:
        feedback_parts.append("Compliance email missing")

    # Verify Master Briefing File (20 pts)
    # Breakdown: 10 pts existence/size, 10 pts structure
    file_score = 0
    if briefing_file.get('exists') and briefing_file.get('created_during_task'):
        content = briefing_file.get('content', '')
        if len(content) > 200:
            file_score += 10
            
            # Check for structure (headings or keywords from multiple domains)
            domains_covered = 0
            lower_content = content.lower()
            
            # Naive check for domain coverage in text file
            eng_hits = any(k in lower_content for k in content_keywords['engineering'])
            infra_hits = any(k in lower_content for k in content_keywords['infrastructure'])
            comp_hits = any(k in lower_content for k in content_keywords['compliance'])
            
            if eng_hits: domains_covered += 1
            if infra_hits: domains_covered += 1
            if comp_hits: domains_covered += 1
            
            if domains_covered >= 2:
                file_score += 10
                feedback_parts.append(f"Master briefing file good ({domains_covered} areas covered)")
            else:
                feedback_parts.append(f"Master briefing file lacks breadth ({domains_covered} areas)")
        else:
            feedback_parts.append("Master briefing file too short")
    else:
        feedback_parts.append("Master briefing file not created")
    
    score += file_score

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback_parts)
    }