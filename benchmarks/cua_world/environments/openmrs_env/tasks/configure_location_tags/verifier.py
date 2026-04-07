#!/usr/bin/env python3
"""
Verifier for configure_location_tags task.

Verifies that the 'Isolation Ward' location has been tagged with:
1. 'Admission Location'
2. 'Transfer Location'
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_location_tags(traj, env_info, task_info):
    """
    Verify that the location tags were correctly applied.
    """
    # 1. Setup - Get copy helper
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Define expectations
    REQUIRED_TAGS = {"Admission Location", "Transfer Location"}

    # 3. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluate Criteria
    found_tags = set(result.get("found_tags", []))
    is_retired = result.get("is_retired", False)
    location_name = result.get("location_name", "Unknown")

    score = 0
    feedback_parts = []
    
    # Check if location was deleted/retired
    if is_retired:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Critical Error: Location '{location_name}' was retired/deleted instead of configured."
        }

    # Navigation/Interaction (implied by any change)
    initial_count = int(result.get("initial_tag_count", 0))
    if len(found_tags) > initial_count:
        score += 20
        feedback_parts.append("Location configuration modified")

    # Check for Admission Location (40 pts)
    if "Admission Location" in found_tags:
        score += 40
        feedback_parts.append("'Admission Location' tag applied")
    else:
        feedback_parts.append("'Admission Location' tag MISSING")

    # Check for Transfer Location (40 pts)
    if "Transfer Location" in found_tags:
        score += 40
        feedback_parts.append("'Transfer Location' tag applied")
    else:
        feedback_parts.append("'Transfer Location' tag MISSING")

    # 5. Final Result
    # Must have BOTH tags to pass (threshold 100)
    passed = (REQUIRED_TAGS.issubset(found_tags))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }