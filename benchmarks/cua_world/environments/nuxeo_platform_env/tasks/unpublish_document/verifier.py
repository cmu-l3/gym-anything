#!/usr/bin/env python3
"""
Verifier for unpublish_document task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_unpublish_document(traj, env_info, task_info):
    """
    Verify that the document was unpublished (removed from section)
    BUT the original document remains in the workspace.
    """
    # 1. Setup copy from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result JSON
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

    # 3. Extract metrics
    original_exists = result.get("original_exists", False)
    original_is_trashed = result.get("original_is_trashed", False)
    section_proxy_count = result.get("section_proxy_count", -1)

    score = 0
    feedback = []

    # Criterion 1: Proxy Removed from Section (40 pts)
    # Ideally count should be 0.
    if section_proxy_count == 0:
        score += 40
        feedback.append("Success: Document removed from 'Employee-Portal' section.")
    elif section_proxy_count > 0:
        feedback.append("Failure: Document still visible in 'Employee-Portal' section.")
    else:
        feedback.append("Error checking section content.")

    # Criterion 2: Original Preserved in Workspace (60 pts)
    # Must exist AND not be trashed.
    if original_exists and not original_is_trashed:
        score += 60
        feedback.append("Success: Original document preserved in 'HR-Internal' workspace.")
    elif original_exists and original_is_trashed:
        # Agent deleted the original instead of unpublishing!
        score = 0 
        feedback.append("CRITICAL FAILURE: You deleted the original document to the trash!")
    else:
        # Original completely gone
        score = 0
        feedback.append("CRITICAL FAILURE: Original document is missing/deleted.")

    # Pass logic
    # Must have both: removed proxy AND kept original.
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }