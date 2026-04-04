#!/usr/bin/env python3
"""Verifier for organize_saved_replies task."""

import json
import tempfile
import os
import time

def verify_organize_saved_replies(traj, env_info, task_info):
    """
    Verify that the agent organized the saved replies correctly.
    
    Criteria:
    1. 'Billing' category exists (25 pts)
    2. Saved reply was renamed to 'Standard Refund' (25 pts)
    3. Saved reply was moved to 'Billing' category (30 pts)
    4. Saved reply was updated recently (anti-gaming) (10 pts)
    5. Original reply ID was preserved (implicit in checks) (10 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_category = metadata.get('target_category', 'Billing')
    expected_reply_name = metadata.get('target_reply_name', 'Standard Refund')

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
    category_exists = result.get('category_exists', False)
    category_id = result.get('category_id')
    reply_exists = result.get('reply_exists', False)
    reply_name = result.get('reply_name', '')
    reply_category_id = result.get('reply_category_id')
    reply_updated_at = int(result.get('reply_updated_at', 0))
    task_start_time = int(result.get('task_start_time', 0))

    # Criterion 1: Category exists
    if category_exists:
        score += 25
        feedback_parts.append(f"Category '{expected_category}' created")
    else:
        feedback_parts.append(f"Category '{expected_category}' NOT found")

    # Criterion 2: Reply renamed
    if not reply_exists:
        feedback_parts.append("Original saved reply missing/deleted")
    else:
        # Check name (case-insensitive)
        if reply_name.lower().strip() == expected_reply_name.lower().strip():
            score += 25
            feedback_parts.append(f"Reply renamed to '{reply_name}'")
        else:
            feedback_parts.append(f"Reply name incorrect: expected '{expected_reply_name}', got '{reply_name}'")
        
        # Criterion 3: Reply moved to category
        if category_exists and reply_category_id == category_id:
            score += 30
            feedback_parts.append("Reply moved to correct category")
        elif reply_category_id is None:
            feedback_parts.append("Reply is still Uncategorized")
        else:
            feedback_parts.append("Reply moved to WRONG category")

        # Criterion 4: Timestamp check (Anti-gaming)
        if reply_updated_at > task_start_time:
            score += 10
            feedback_parts.append("Modification time valid")
        else:
            feedback_parts.append("Reply not modified during task")
            
        # Criterion 5: ID Preserved (Implicit: we looked up by ID and found it)
        score += 10
        feedback_parts.append("Original reply modified (ID preserved)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }