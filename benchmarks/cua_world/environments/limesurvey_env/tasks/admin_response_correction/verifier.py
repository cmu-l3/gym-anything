#!/usr/bin/env python3
"""
Verifier for Admin Response Correction task.

Task:
1. Locate response for 'michael.chang@acmecorp.com'
2. Change satisfaction score from 1 to 5.
3. Add admin note containing "ticket #8842" to comments.

Verification:
- Check database for the specific response row.
- Verify column values.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_admin_response_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_score = metadata.get('expected_score_code', '5')
    expected_snippet = metadata.get('expected_comment_snippet', 'ticket #8842')

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

    # Check if response was found
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target response (michael.chang@acmecorp.com) not found in database. Did you delete it?"
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Satisfaction Score (40 pts)
    # The value should be the code '5'
    actual_score = str(result.get('satisfaction', ''))
    if actual_score == expected_score:
        score += 40
        feedback_parts.append("Satisfaction score updated to 5 correctly")
    elif actual_score == "1":
        feedback_parts.append("Satisfaction score unchanged (still 1)")
    else:
        feedback_parts.append(f"Satisfaction score incorrect (expected 5, got {actual_score})")

    # 2. Check Admin Comment (30 pts)
    actual_comment = str(result.get('comment', '') or "")
    # Check for the ticket number
    if expected_snippet.lower() in actual_comment.lower():
        score += 30
        feedback_parts.append(f"Admin note added ({expected_snippet})")
    else:
        feedback_parts.append(f"Admin note missing ticket reference '{expected_snippet}'")

    # 3. Check Modification (Response ID persistence) (30 pts)
    # If the response ID exists, it means the record is there. 
    # Ideally we'd check if it's the SAME ID as start, but we didn't export start ID to verifier.
    # However, if the user successfully edited the record instead of deleting/re-adding, 
    # the ID should persist. Since we just check values here, we award points for having the record 
    # with correct values. 
    # Let's interpret "Response Modified" as "Not in original state".
    
    # Original state: Score 1, Comment "Service was quick..."
    # If both changed correctly, we assume modification.
    
    modification_points = 0
    if actual_score != "1":
        modification_points += 15
    if expected_snippet.lower() in actual_comment.lower():
        modification_points += 15
    
    score += modification_points
    if modification_points > 0:
        feedback_parts.append("Record modified successfully")

    # Final tally
    # Total possible: 40 + 30 + 30 = 100
    
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }