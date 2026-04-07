#!/usr/bin/env python3
"""
Verifier for contributor_summit_outreach task.

Task Requirements:
1. Create 'Summit-Candidates' folder.
2. Populate with UNIQUE senders from SpamAssassin threads (Deduplication).
3. Draft email to events@apache.org.
4. Use BCC for the candidates.

Scoring:
- Folder existence (10 pts)
- Volume: 5+ emails in folder (15 pts)
- Deduplication: 100% unique senders (30 pts)
- Draft creation & Recipient (10 pts)
- BCC usage: 5+ addresses in BCC (20 pts)
- Address matching: BCC list matches folder contents (15 pts)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contributor_summit_outreach(traj, env_info, task_info):
    """Verify the deduplication and confidential outreach task."""
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    target_folder = metadata.get('target_folder', 'Summit-Candidates')
    min_candidates = metadata.get('min_candidates', 5)
    
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
    feedback_parts = []
    
    # Data from result
    folder_exists = result.get('folder_exists', False)
    candidate_emails = result.get('candidates', [])
    drafts = result.get('drafts', [])
    
    # --- Criterion 1: Folder Creation (10 pts) ---
    if folder_exists:
        score += 10
        feedback_parts.append(f"Folder '{target_folder}' created")
    else:
        feedback_parts.append(f"Folder '{target_folder}' NOT found")

    # --- Criterion 2: Volume (15 pts) ---
    count = len(candidate_emails)
    if count >= min_candidates:
        score += 15
        feedback_parts.append(f"Sufficient candidates found ({count})")
    elif count > 0:
        partial = int(15 * (count / min_candidates))
        score += partial
        feedback_parts.append(f"Insufficient candidates ({count}/{min_candidates})")
    else:
        feedback_parts.append("No candidates in folder")

    # --- Criterion 3: Deduplication (30 pts) ---
    # Check if senders in the folder are unique
    senders = [c.get('sender', '').lower() for c in candidate_emails if c.get('sender')]
    unique_senders = set(senders)
    
    if count > 0:
        uniqueness_ratio = len(unique_senders) / len(senders)
        # We enforce a strict penalty for duplicates as that's the core cognitive task
        dedupe_score = int(30 * uniqueness_ratio)
        
        # Bonus penalty: If ratio is too low (<0.8), they failed the core concept
        if uniqueness_ratio < 0.8:
            dedupe_score = 0
            feedback_parts.append("Failed deduplication: Too many duplicates moved")
        else:
            feedback_parts.append(f"Deduplication ratio: {uniqueness_ratio:.2f}")
            
        score += dedupe_score
    elif folder_exists:
        feedback_parts.append("No emails to check for duplicates")

    # --- Criterion 4: Draft Creation (10 pts) ---
    target_draft = None
    for d in drafts:
        # Check if to events@apache.org (allowing for loose matching)
        if 'events@apache.org' in d.get('to', '').lower():
            target_draft = d
            break
            
    if target_draft:
        score += 10
        feedback_parts.append("Draft to 'events@apache.org' found")
    else:
        feedback_parts.append("No draft to 'events@apache.org' found")

    # --- Criterion 5: BCC Usage (20 pts) ---
    bcc_score = 0
    bcc_addrs = []
    if target_draft:
        bcc_header = target_draft.get('bcc', '')
        # Extract emails from BCC string
        bcc_addrs = re.findall(r'[\w\.-]+@[\w\.-]+', bcc_header)
        
        if len(bcc_addrs) >= min_candidates:
            bcc_score = 20
            feedback_parts.append(f"BCC populated correctly ({len(bcc_addrs)} addresses)")
        elif len(bcc_addrs) > 0:
            bcc_score = 10
            feedback_parts.append(f"BCC partially populated ({len(bcc_addrs)} addresses)")
        else:
            # Check if they put them in To/CC instead (fail safe check)
            to_cc_addrs = re.findall(r'[\w\.-]+@[\w\.-]+', target_draft.get('to', '') + target_draft.get('cc', ''))
            if len(to_cc_addrs) > 3:
                feedback_parts.append("Privacy FAIL: Recipients found in To/CC instead of BCC")
            else:
                feedback_parts.append("BCC field empty")
    
    score += bcc_score

    # --- Criterion 6: Address Matching (15 pts) ---
    # Do the BCC addresses match the folder contents?
    match_score = 0
    if target_draft and len(unique_senders) > 0:
        # Normalize sets
        bcc_set = set(addr.lower() for addr in bcc_addrs)
        
        # Calculate intersection
        matches = unique_senders.intersection(bcc_set)
        match_ratio = len(matches) / len(unique_senders) if len(unique_senders) > 0 else 0
        
        if match_ratio > 0.8:
            match_score = 15
            feedback_parts.append("Draft recipients match folder contents")
        elif match_ratio > 0.4:
            match_score = 7
            feedback_parts.append("Partial match between draft and folder")
        else:
            feedback_parts.append("Draft recipients do not match folder contents")
            
    score += match_score

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }