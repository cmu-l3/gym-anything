#!/usr/bin/env python3
"""
Verifier for configure_server_config_map task.

Checks:
1. API returns expected Configuration Map entries (Key/Value).
2. Each entry has a non-empty comment (required by task).
3. Database persistence confirmed.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_server_config_map(traj, env_info, task_info):
    """Verify that the Configuration Map was populated correctly."""
    
    # Use copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected entries from metadata
    metadata = task_info.get('metadata', {})
    expected_entries = metadata.get('expected_entries', {})
    
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

    actual_entries = result.get('entries', {})
    db_verified = result.get('db_persistence_verified', False)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check each expected entry
    correct_entries = 0
    total_entries = len(expected_entries)
    entries_with_comments = 0
    
    for key, expected_value in expected_entries.items():
        if key in actual_entries:
            actual_data = actual_entries[key]
            actual_value = actual_data.get('value', '')
            actual_comment = actual_data.get('comment', '')
            
            # Check value (8 points each)
            if actual_value == expected_value:
                score += 8
                correct_entries += 1
            else:
                feedback_parts.append(f"Key '{key}': Expected '{expected_value}', got '{actual_value}'")
                
            # Check comment (part of bonus)
            if actual_comment and len(actual_comment.strip()) > 0:
                entries_with_comments += 1
        else:
            feedback_parts.append(f"Missing key: '{key}'")

    # Bonus points for comments
    # 20 points allocated for comments across 10 entries (2 points each)
    comment_score = entries_with_comments * 2
    score += comment_score
    
    if entries_with_comments < total_entries:
        feedback_parts.append(f"Missing comments on {total_entries - entries_with_comments} entries")

    # Anti-gaming: Ensure DB persistence
    if not db_verified and correct_entries > 0:
        score = int(score * 0.5) # Penalize if API reports success but DB doesn't match (unlikely but possible caching issue)
        feedback_parts.append("WARNING: Database persistence could not be verified")
    
    # Summary feedback
    feedback_parts.insert(0, f"Found {correct_entries}/{total_entries} correct entries")
    feedback_parts.insert(1, f"Found {entries_with_comments}/{total_entries} comments")

    # Pass threshold: 70 points
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100), # Cap at 100
        "feedback": "\n".join(feedback_parts)
    }