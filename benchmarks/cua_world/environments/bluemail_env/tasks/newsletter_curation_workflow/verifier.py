#!/usr/bin/env python3
"""
Verifier for newsletter_curation_workflow task.

Scoring Criteria (100 pts total):
1. Organization (20 pts):
   - Folder 'Newsletter-Material' exists (10 pts)
   - Folder contains exactly 3 emails (10 pts)
   
2. Curation Diversity (20 pts):
   - The 3 emails must come from at least 2 different mailing lists.
   
3. Communication (10 pts):
   - A draft (or sent email) to 'subscribers@tech-weekly.com' exists.
   
4. Consistency/Synthesis (50 pts):
   - The body of the draft must contain the Subject lines of the emails 
     inside the folder. This proves the agent actually summarized the 
     specific emails it curated, connecting the two actions.
     (roughly 16 pts per matching subject)

Pass threshold: 70 points.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_subject(subj):
    """Normalize subject for comparison (remove Re:, Fwd:, whitespace)."""
    if not subj: return ""
    s = str(subj).lower()
    s = re.sub(r'^(re|fwd):\s*', '', s)
    s = re.sub(r'\s+', ' ', s)
    return s.strip()

def extract_list_name(list_id):
    """Extract a readable list name from List-Id header."""
    # Common format: <sadev.spamassassin.org> or "List Name" <list.domain>
    if not list_id: return "unknown"
    match = re.search(r'<([^>]+)>', list_id)
    if match:
        return match.group(1).lower()
    return list_id.lower()

def verify_newsletter_curation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_folder = metadata.get('target_folder', 'Newsletter-Material')
    expected_count = metadata.get('target_count', 3)
    min_sources = metadata.get('min_sources', 2)
    recipient = metadata.get('draft_recipient', 'subscribers@tech-weekly.com')

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
    
    # 1. Check Folder
    if result.get('folder_exists'):
        score += 10
        feedback.append(f"Folder '{target_folder}' created.")
    else:
        feedback.append(f"Folder '{target_folder}' NOT found.")

    # 2. Check Count
    curated = result.get('curated_emails', [])
    count = len(curated)
    if count == expected_count:
        score += 10
        feedback.append(f"Correctly curated {count} emails.")
    else:
        feedback.append(f"Folder contains {count} emails (expected {expected_count}).")

    # 3. Check Diversity
    # We only check diversity if there are emails to check
    if count > 0:
        list_ids = set()
        for email in curated:
            lid = extract_list_name(email.get('list_id', ''))
            # Fallback heuristics if List-Id is empty
            if not lid or lid == "unknown":
                # Try to guess from subject prefix like [ILUG]
                subj = email.get('subject', '')
                m = re.match(r'\[([\w-]+)\]', subj)
                if m:
                    lid = m.group(1).lower()
                else:
                    # Fallback to sender domain?? No, let's keep it strict or treat as unique unknown
                    lid = "unknown_" + str(hash(email.get('subject'))) 
            
            list_ids.add(lid)
        
        if len(list_ids) >= min_sources:
            score += 20
            feedback.append(f"Diversity check passed: Found sources {list(list_ids)}.")
        else:
            feedback.append(f"Diversity check failed: All emails appear to be from {list(list_ids)}.")
    
    # 4. Check Draft/Sent Email
    target_email = None
    all_outgoing = result.get('drafts', []) + result.get('sent', [])
    
    for email in all_outgoing:
        if recipient.lower() in str(email.get('to', '')).lower():
            target_email = email
            break
            
    if target_email:
        score += 10
        feedback.append(f"Draft/Email to {recipient} found.")
    else:
        feedback.append(f"No draft/email found addressed to {recipient}.")

    # 5. Consistency Check (Subject Matching)
    # The body of the draft should contain the subjects of the curated emails
    if target_email and count > 0:
        body = target_email.get('body', '').lower()
        matches = 0
        
        for email in curated:
            subj_raw = email.get('subject', '')
            # Clean subject for search (remove RE:, [List], etc)
            # We look for substantial substrings
            clean_subj = normalize_subject(subj_raw)
            # Remove [tags] if strictly matching
            clean_subj_no_tags = re.sub(r'\[.*?\]', '', clean_subj).strip()
            
            # We accept match if a significant portion of the subject is in the body
            if len(clean_subj_no_tags) > 5 and clean_subj_no_tags in body:
                matches += 1
            elif len(clean_subj) > 5 and clean_subj in body:
                matches += 1
        
        # Calculate score: 50 points distributed across expected_count
        points_per_match = 50 / expected_count
        match_score = int(matches * points_per_match)
        # Cap at 50
        match_score = min(50, match_score)
        
        score += match_score
        feedback.append(f"Content Consistency: {matches}/{count} curated email subjects found in draft body (+{match_score} pts).")
    elif not target_email:
        feedback.append("Cannot check content consistency (no draft found).")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }