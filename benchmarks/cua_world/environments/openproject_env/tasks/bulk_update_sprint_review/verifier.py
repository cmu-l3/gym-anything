#!/usr/bin/env python3
"""
Verifier for bulk_update_sprint_review task.

Checks:
1. WP1 ("Fix broken checkout..."): Status="In progress", Assignee="Alice Johnson"
2. WP2 ("Implement product..."): Status="In progress", Assignee="Carol Williams"
3. WP3 ("Implement product search..."): Comment contains specific text
4. Anti-gaming: Verifies changes occurred after task start time
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_update(traj, env_info, task_info):
    """
    Verify the three work packages were updated correctly.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define expectations
    exp_wp1_status = metadata.get('wp1_expected_status', 'In progress')
    exp_wp1_assignee = metadata.get('wp1_expected_assignee', 'Alice Johnson')
    
    exp_wp2_status = metadata.get('wp2_expected_status', 'In progress')
    exp_wp2_assignee = metadata.get('wp2_expected_assignee', 'Carol Williams')
    
    exp_wp3_comment = metadata.get('wp3_expected_comment_fragment', 'Blocked by Elasticsearch cluster upgrade - ETA next Wednesday')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)
    
    # Helper for normalization
    def norm(s): return str(s).strip().lower() if s else ""

    # --- Verify WP1: Fix broken checkout ---
    wp1 = result.get('wp1')
    if wp1 and wp1.get('found'):
        # Check Status (17 pts)
        actual_status = wp1.get('status')
        if norm(actual_status) == norm(exp_wp1_status):
            score += 17
            feedback_parts.append("WP1 Status: OK")
        else:
            feedback_parts.append(f"WP1 Status: Expected '{exp_wp1_status}', got '{actual_status}'")
            
        # Check Assignee (18 pts)
        actual_assignee = wp1.get('assignee')
        if norm(actual_assignee) == norm(exp_wp1_assignee):
            score += 18
            feedback_parts.append("WP1 Assignee: OK")
        else:
            feedback_parts.append(f"WP1 Assignee: Expected '{exp_wp1_assignee}', got '{actual_assignee}'")
            
        # Anti-gaming check
        if wp1.get('updated_at', 0) <= task_start:
            feedback_parts.append("WARNING: WP1 was not modified during this task session.")
    else:
        feedback_parts.append("WP1: Not found or deleted")

    # --- Verify WP2: Implement product recommendation engine ---
    wp2 = result.get('wp2')
    if wp2 and wp2.get('found'):
        # Check Status (17 pts)
        actual_status = wp2.get('status')
        if norm(actual_status) == norm(exp_wp2_status):
            score += 17
            feedback_parts.append("WP2 Status: OK")
        else:
            feedback_parts.append(f"WP2 Status: Expected '{exp_wp2_status}', got '{actual_status}'")

        # Check Assignee (18 pts)
        actual_assignee = wp2.get('assignee')
        if norm(actual_assignee) == norm(exp_wp2_assignee):
            score += 18
            feedback_parts.append("WP2 Assignee: OK")
        else:
            feedback_parts.append(f"WP2 Assignee: Expected '{exp_wp2_assignee}', got '{actual_assignee}'")
    else:
        feedback_parts.append("WP2: Not found or deleted")

    # --- Verify WP3: Elasticsearch Comment ---
    wp3 = result.get('wp3')
    if wp3 and wp3.get('found'):
        # Check for comment (30 pts)
        journals = wp3.get('journals', [])
        comment_found = False
        
        # Search all journals for the expected text
        # Also enforce that the specific comment was created *after* task start
        for j in journals:
            # We check if the note contains the specific text (case-insensitive)
            if norm(exp_wp3_comment) in norm(j.get('notes', '')):
                # Check timestamp to prevent reading pre-seeded comments (if any)
                if j.get('created_at', 0) > task_start:
                    comment_found = True
                    break
        
        if comment_found:
            score += 30
            feedback_parts.append("WP3 Comment: OK")
        else:
            feedback_parts.append("WP3 Comment: Expected comment not found (or created before task start)")
    else:
        feedback_parts.append("WP3: Not found or deleted")

    # 3. Final Result
    passed = score >= 60
    
    # Format feedback
    feedback_str = f"Score: {score}/100. " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }