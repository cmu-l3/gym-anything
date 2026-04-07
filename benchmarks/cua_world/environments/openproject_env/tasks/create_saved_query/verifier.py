#!/usr/bin/env python3
"""
Verifier for create_saved_query task in OpenProject.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_saved_query(traj, env_info, task_info):
    """
    Verify that the 'Bobs Backlog Items' query was created with correct filters.
    
    Scoring:
    - 25 pts: Query exists with exact name
    - 25 pts: Query is associated with the correct project
    - 25 pts: Status filter 'New' is present
    - 25 pts: Assignee filter 'Bob Smith' is present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Rails verification data
    rails_data = result.get("rails_verification", {})
    if not rails_data:
        return {"passed": False, "score": 0, "feedback": "No verification data returned from OpenProject."}

    if rails_data.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {rails_data.get('error')}"}

    score = 0
    feedback_parts = []

    # Criterion 1: Query Found (25 pts)
    if rails_data.get("found"):
        score += 25
        feedback_parts.append("PASS: Query 'Bobs Backlog Items' created.")
    else:
        feedback_parts.append("FAIL: Query 'Bobs Backlog Items' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Project Match (25 pts)
    if rails_data.get("project_match"):
        score += 25
        feedback_parts.append("PASS: Linked to correct project.")
    else:
        feedback_parts.append("FAIL: Linked to wrong project (or global).")

    # Criterion 3: Status Filter (25 pts)
    if rails_data.get("has_status_filter"):
        score += 25
        feedback_parts.append("PASS: Filtered by Status 'New'.")
    else:
        feedback_parts.append("FAIL: Missing or incorrect Status filter.")

    # Criterion 4: Assignee Filter (25 pts)
    if rails_data.get("has_assignee_filter"):
        score += 25
        feedback_parts.append("PASS: Filtered by Assignee 'Bob Smith'.")
    else:
        feedback_parts.append("FAIL: Missing or incorrect Assignee filter.")

    # Pass Threshold
    passed = score >= 50
    
    # Extra check for Anti-gaming: Ensure it wasn't pre-existing
    # (setup_task.sh deletes it, so if found, it must be created during task)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": rails_data
    }