#!/usr/bin/env python3
"""
Verifier for discussion_flow_organization task.

Criteria:
1. Folders 'New-Topics' and 'Ongoing-Discussions' created (10 pts)
2. 'Ongoing-Discussions' contains replies (Re:, Fwd:) (25 pts)
3. 'New-Topics' contains clean subjects (25 pts)
4. Inbox cleared (<5 remaining) (10 pts)
5. Digest file created with correct content (15 pts)
6. Triage email drafted (15 pts)

Total: 100 pts
Pass: 75 pts
"""

import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_reply_or_forward(subject):
    """
    Check if subject indicates a reply or forward.
    Matches:
    - Re: ...
    - Fwd: ...
    - AW: ... (German)
    - [List] Re: ...
    - Re[2]: ...
    """
    # Regex for standard prefixes, case insensitive
    # ^\s* : Start with optional whitespace
    # (\[.*?\]\s*)? : Optional tag in brackets like [SAdev]
    # (re|fw|fwd|aw|sv|vs) : Prefix code
    # (\s*\[\d+\])? : Optional count like [2]
    # : : Colon separator
    pattern = r'^\s*(\[.*?\]\s*)?(re|fw|fwd|aw|sv|vs)(\s*\[\d+\])?\s*:'
    return bool(re.match(pattern, subject, re.IGNORECASE))

def verify_discussion_flow_organization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []
    
    folders = result.get('folders', {})
    new_topics_data = folders.get('New-Topics', {'exists': False, 'count': 0, 'subjects': []})
    ongoing_data = folders.get('Ongoing-Discussions', {'exists': False, 'count': 0, 'subjects': []})
    inbox_data = folders.get('INBOX', {'exists': True, 'count': 50, 'subjects': []})
    digest = result.get('digest', {})
    
    # 1. Folders Created (10 pts)
    if new_topics_data['exists'] and ongoing_data['exists']:
        score += 10
        feedback.append("Both required folders created.")
    elif new_topics_data['exists'] or ongoing_data['exists']:
        score += 5
        feedback.append("Only one required folder created.")
    else:
        feedback.append("No custom folders created.")

    # 2. Sorting Accuracy - Ongoing (25 pts)
    # Penalize for non-replies in Ongoing
    ongoing_subjects = ongoing_data['subjects']
    if ongoing_subjects:
        correct_ongoing = sum(1 for s in ongoing_subjects if is_reply_or_forward(s))
        incorrect_ongoing = len(ongoing_subjects) - correct_ongoing
        
        # Calculate accuracy score
        # Allow small margin of error (e.g. 1-2 mistakes)
        accuracy = correct_ongoing / len(ongoing_subjects)
        pts = int(25 * accuracy)
        
        # Heavy penalty for moving non-replies here (false positives)
        if incorrect_ongoing > 0:
            pts -= (incorrect_ongoing * 2)
        
        pts = max(0, pts)
        score += pts
        feedback.append(f"Ongoing-Discussions sorting: {correct_ongoing}/{len(ongoing_subjects)} correct ({pts} pts).")
    else:
        feedback.append("Ongoing-Discussions folder is empty.")

    # 3. Sorting Accuracy - New Topics (25 pts)
    # Penalize for replies in New Topics
    new_subjects = new_topics_data['subjects']
    if new_subjects:
        correct_new = sum(1 for s in new_subjects if not is_reply_or_forward(s))
        incorrect_new = len(new_subjects) - correct_new
        
        accuracy = correct_new / len(new_subjects)
        pts = int(25 * accuracy)
        
        if incorrect_new > 0:
            pts -= (incorrect_new * 2)
            
        pts = max(0, pts)
        score += pts
        feedback.append(f"New-Topics sorting: {correct_new}/{len(new_subjects)} correct ({pts} pts).")
    else:
        feedback.append("New-Topics folder is empty.")

    # 4. Inbox Cleared (10 pts)
    final_inbox_count = inbox_data['count']
    if final_inbox_count < 5:
        score += 10
        feedback.append(f"Inbox cleared effectively ({final_inbox_count} remaining).")
    elif final_inbox_count < 15:
        score += 5
        feedback.append(f"Inbox partially cleared ({final_inbox_count} remaining).")
    else:
        feedback.append(f"Inbox not cleared ({final_inbox_count} remaining).")

    # 5. Digest Creation (15 pts)
    if digest.get('exists') and digest.get('created_in_task'):
        content = digest.get('content', '')
        # Check if it contains subjects from New-Topics
        matches = 0
        # Check first 5 subjects to avoid massive regex
        check_subjects = new_subjects[:5] if new_subjects else []
        for s in check_subjects:
            if s and s in content:
                matches += 1
        
        if matches > 0 or (len(check_subjects) == 0 and len(content) > 10):
            score += 15
            feedback.append("Digest file created with relevant content.")
        else:
            score += 5
            feedback.append("Digest file created but content mismatch.")
    else:
        feedback.append("Digest file not created or not modified.")

    # 6. Triage Email (15 pts)
    if result.get('triage_email_found'):
        score += 15
        feedback.append("Triage email found.")
    else:
        feedback.append("No email found addressed to triage-team.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }