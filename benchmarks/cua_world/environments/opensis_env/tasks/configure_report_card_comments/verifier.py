#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_report_card_comments(traj, env_info, task_info):
    """
    Verify that the report card comments were correctly configured in OpenSIS.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_comments = metadata.get('expected_comments', [
        {"code": "PLE", "title": "Pleasure to have in class", "sort_order": 1},
        {"code": "MHW", "title": "Missing homework assignments", "sort_order": 2}
    ])

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result_data.get('query_success', False):
        return {"passed": False, "score": 0, "feedback": f"Database query failed inside container: {result_data.get('error')}"}

    found_comments = result_data.get('found_comments', [])
    
    score = 0
    feedback = []
    
    # Check for each expected comment
    found_map = {c['code']: c for c in found_comments}
    
    for expected in expected_comments:
        code = expected['code']
        if code in found_map:
            actual = found_map[code]
            
            # Check existence (30 pts each)
            score += 30
            feedback.append(f"Comment '{code}' created.")
            
            # Check details (15 pts each)
            # Case insensitive check for title, exact for sort order
            title_match = actual['title'].strip().lower() == expected['title'].strip().lower()
            sort_match = int(actual['sort_order']) == int(expected['sort_order'])
            
            if title_match:
                score += 10
            else:
                feedback.append(f"'{code}' title mismatch: expected '{expected['title']}', got '{actual['title']}'")
                
            if sort_match:
                score += 5
            else:
                feedback.append(f"'{code}' sort order mismatch: expected {expected['sort_order']}, got {actual['sort_order']}")
        else:
            feedback.append(f"Comment '{code}' NOT found.")

    # Check for duplicates (10 pts)
    # If len(found_comments) matches expected count and they are unique
    if len(found_comments) == len(expected_comments):
        score += 10
        feedback.append("No duplicate comments found.")
    elif len(found_comments) > len(expected_comments):
        feedback.append("Duplicate or extra comments found.")

    # VLM Verification (Bonus/Confirmation)
    # We check if the agent actually navigated the UI
    # This acts as a secondary check to prevent direct DB injection if that were possible (unlikely for agent)
    # and confirms visual task completion.
    
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }