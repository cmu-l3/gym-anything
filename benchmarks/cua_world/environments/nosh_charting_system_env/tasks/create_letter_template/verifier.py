#!/usr/bin/env python3
"""
Verifier for create_letter_template task.
Verifies that the agent created a document template with the specific title and content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_letter_template(traj, env_info, task_info):
    """
    Verifies the template creation task.
    
    Scoring Criteria:
    1. Template record found in DB (30 pts)
    2. Template title matches 'New Patient Welcome' (30 pts)
    3. Template content contains key phrases (40 pts)
    """
    
    # 1. Setup and Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Result Data
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "New Patient Welcome")
    # Retrieve required phrase from metadata or fall back to description text
    required_phrase = "We are honored that you have chosen us"
    
    found_record = result.get('found_record', False)
    found_title = result.get('found_title', "")
    content_match = result.get('full_content_match', False)
    
    # 3. Calculate Score
    score = 0
    feedback_parts = []
    
    # Check 1: Record Existence (30 pts)
    if found_record:
        score += 30
        feedback_parts.append("Template record found in database.")
    else:
        feedback_parts.append("No template record found.")
        return {"passed": False, "score": 0, "feedback": "Failed: No template found in database."}

    # Check 2: Title Match (30 pts)
    # Case-insensitive comparison
    if expected_title.lower() in found_title.lower():
        score += 30
        feedback_parts.append(f"Title matches '{expected_title}'.")
    else:
        feedback_parts.append(f"Title mismatch. Expected '{expected_title}', found '{found_title}'.")
        # Allow partial credit if record exists but title is slightly off? No, stricter is better.
    
    # Check 3: Content Match (40 pts)
    if content_match:
        score += 40
        feedback_parts.append("Content body matches required text.")
    else:
        feedback_parts.append("Content body missing required phrases.")

    # 4. Final Determination
    passed = (score >= 80) # Requires existence + title + content match (at least mostly)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }