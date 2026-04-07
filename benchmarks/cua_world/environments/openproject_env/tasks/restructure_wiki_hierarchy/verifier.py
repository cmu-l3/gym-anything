#!/usr/bin/env python3
"""
Verifier for restructure_wiki_hierarchy task.

Verifies:
1. Parent page "Technical Documentation" exists and was created during the task.
2. Parent page contains the Table of Contents macro.
3. "System Architecture" page is a child of the new parent.
4. "API Endpoints" page is a child of the new parent.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restructure_wiki_hierarchy(traj, env_info, task_info):
    """
    Verify the wiki hierarchy structure using database state exported from Rails.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    # Check for script errors
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Internal verification error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    parent_id = result.get('parent_id')
    
    # 1. Verify Parent Page Creation (30 pts)
    # Must exist AND have been created after task start (anti-gaming)
    if result.get('parent_exists'):
        created_at = result.get('parent_created_at', 0)
        # Allow 60s tolerance for clock skew, though docker usually syncs
        if created_at >= (task_start - 60):
            score += 30
            feedback_parts.append("Parent page 'Technical Documentation' created successfully.")
        else:
            feedback_parts.append("Parent page exists but was created BEFORE task start (stale data).")
    else:
        feedback_parts.append("Parent page 'Technical Documentation' NOT found.")

    # 2. Verify Table of Contents (10 pts)
    if result.get('has_toc'):
        score += 10
        feedback_parts.append("Table of Contents macro found.")
    else:
        feedback_parts.append("Table of Contents macro ({{toc}}) missing from parent page.")

    # 3. Verify Child 1 Move (30 pts)
    child1_parent = result.get('child1_parent_id')
    if child1_parent is not None and child1_parent == parent_id:
        score += 30
        feedback_parts.append("'System Architecture' is correctly nested under parent.")
    else:
        feedback_parts.append("'System Architecture' is NOT a child of the new parent.")

    # 4. Verify Child 2 Move (30 pts)
    child2_parent = result.get('child2_parent_id')
    if child2_parent is not None and child2_parent == parent_id:
        score += 30
        feedback_parts.append("'API Endpoints' is correctly nested under parent.")
    else:
        feedback_parts.append("'API Endpoints' is NOT a child of the new parent.")

    # Pass threshold: 70 points (Must create parent + move children)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }