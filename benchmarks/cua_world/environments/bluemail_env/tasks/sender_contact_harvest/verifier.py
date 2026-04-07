#!/usr/bin/env python3
"""
Verifier for sender_contact_harvest task.

Scoring Criteria:
1. Contact List File (65 points total)
   - File exists: 10 pts
   - Created during task: 5 pts
   - Quantity: >= 15 unique valid emails (20 pts), scaled down if fewer
   - Quality: >= 80% of extracted emails match real inbox senders (20 pts)
   - Formatting: 10 pts (detected by having valid email patterns)

2. Draft Email (25 points total)
   - Draft exists to correct recipient: 15 pts
   - Content relevant (keywords): 10 pts

3. Process & Safety (10 points total)
   - Inbox preserved (didn't delete source data): 10 pts

Pass Threshold: 65 points
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sender_contact_harvest(traj, env_info, task_info):
    """
    Verify that the agent extracted sender emails to a file and drafted an announcement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_unique = metadata.get('min_unique_contacts', 15)
    
    # 1. Retrieve result JSON
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

    # --- Criterion 1: Contact List File (65 pts) ---
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_created_during_task', False)
    unique_count = result.get('extracted_unique_count', 0)
    match_count = result.get('valid_match_count', 0)
    match_pct = result.get('valid_match_pct', 0)

    if file_exists:
        score += 10
        feedback_parts.append("Contact file created")
        
        if file_fresh:
            score += 5
        else:
            feedback_parts.append("(File was not modified during task)")

        # Quantity Score (20 pts max)
        # Full points for >= min_unique, scaled otherwise
        if unique_count >= min_unique:
            score += 20
            feedback_parts.append(f"Quantity requirement met ({unique_count} unique found)")
        elif unique_count > 0:
            quantity_score = int((unique_count / min_unique) * 20)
            score += quantity_score
            feedback_parts.append(f"Partial quantity ({unique_count}/{min_unique})")
        else:
            feedback_parts.append("File contains no valid email patterns")

        # Quality/Accuracy Score (20 pts max)
        # We want to ensure they didn't just hallucinate emails
        if match_pct >= 80:
            score += 20
            feedback_parts.append(f"High accuracy ({match_pct}%)")
        elif match_pct >= 50:
            score += 10
            feedback_parts.append(f"Moderate accuracy ({match_pct}%)")
        elif unique_count > 0:
            score += 0
            feedback_parts.append(f"Low accuracy ({match_pct}% match real senders)")
            
        # Formatting score (10 pts) implied by having parsed any emails
        if unique_count > 0:
            score += 10

    else:
        feedback_parts.append("Contact file NOT found")

    # --- Criterion 2: Draft Email (25 pts) ---
    draft_info = result.get('draft_analysis', {})
    if draft_info.get('found', False):
        if draft_info.get('recipient_correct', False):
            score += 15
            feedback_parts.append("Draft recipient correct")
        else:
            score += 5
            feedback_parts.append("Draft found but wrong recipient")
            
        if draft_info.get('keyword_match', False) or draft_info.get('subject_match', False):
            score += 10
            feedback_parts.append("Draft content relevant")
        else:
            feedback_parts.append("Draft content missing keywords")
    else:
        feedback_parts.append("No relevant draft found")

    # --- Criterion 3: Inbox Preservation (10 pts) ---
    if result.get('inbox_preserved', False):
        score += 10
    else:
        feedback_parts.append("Inbox data was deleted (penalty)")

    # --- Final Evaluation ---
    passed = score >= 65
    
    # Secondary check: Must have at least a file with some correct data to pass
    if match_count < 5:
        passed = False
        feedback_parts.append("FAILED: Too few correct emails extracted")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }