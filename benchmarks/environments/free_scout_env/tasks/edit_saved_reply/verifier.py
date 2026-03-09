#!/usr/bin/env python3
"""
Verifier for edit_saved_reply task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_saved_reply(traj, env_info, task_info):
    """
    Verify that the saved reply was edited correctly.
    
    Criteria:
    1. A saved reply with name "SSO Password Reset Guide" exists.
    2. It contains the new URL and instructions.
    3. It does NOT contain the old URL.
    4. The original saved reply was edited (preferred) OR correctly replaced.
    5. Anti-gaming: Not just creating a duplicate while leaving the old one.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_new_name = metadata.get('new_name', "SSO Password Reset Guide")
    required_strings = metadata.get('required_strings', [])
    forbidden_strings = metadata.get('forbidden_strings', [])

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
    feedback_parts = []
    
    # Extract data
    candidate_found = result.get('candidate_found', False)
    candidate_name = result.get('candidate_name', "")
    candidate_body = result.get('candidate_body', "")
    
    target_still_exists = result.get('target_still_exists', False)
    target_id = result.get('target_id', 0)
    candidate_id = result.get('candidate_id', "")
    
    old_name_exists = result.get('old_name_exists', False)
    
    # --- Scoring ---

    # 1. Correct Name (25 pts)
    if candidate_found and candidate_name.strip() == expected_new_name:
        score += 25
        feedback_parts.append(f"Found saved reply with correct name: '{candidate_name}'")
    elif candidate_found:
        score += 15
        feedback_parts.append(f"Found saved reply with partial name match: '{candidate_name}'")
    else:
        feedback_parts.append("Did not find a saved reply with the expected name")

    # 2. Content Checks (45 pts)
    if candidate_found:
        body_score = 0
        missing = []
        for s in required_strings:
            if s.lower() in candidate_body.lower():
                body_score += 15
            else:
                missing.append(s)
        
        # Cap body score at 45
        if body_score > 45: body_score = 45
        
        score += body_score
        if len(missing) == 0:
            feedback_parts.append("Body content correct")
        else:
            feedback_parts.append(f"Body missing required text: {', '.join(missing)}")
            
        # Check forbidden strings (Old URL)
        has_forbidden = False
        for s in forbidden_strings:
            if s.lower() in candidate_body.lower():
                has_forbidden = True
                score -= 10 # Penalty
                feedback_parts.append(f"Body still contains outdated text: {s}")
        if not has_forbidden:
            feedback_parts.append("Old content successfully removed")
    
    # 3. Edit vs Create (30 pts)
    # Best case: They edited the existing record (Candidate ID == Target ID)
    # Acceptable case: They deleted old and created new (Old name gone, candidate exists)
    
    if candidate_found and str(candidate_id) == str(target_id):
        score += 30
        feedback_parts.append("Correctly edited the existing saved reply (ID persisted)")
    elif candidate_found and not old_name_exists:
        # They likely deleted the old one and created a new one
        # We accept this but maybe slightly less points if we were strict, 
        # but for this task "Edit" usually implies the end state is correct.
        # We'll give 25 points.
        score += 25
        feedback_parts.append("Created new reply and removed old one (ID changed)")
    elif candidate_found and old_name_exists:
        # They created a new one but forgot to delete the old one
        score += 5
        feedback_parts.append("Created new reply but old one still exists (Duplicate)")
    else:
        feedback_parts.append("Verification failed on update method")

    # Final Check
    passed = score >= 80 and candidate_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }