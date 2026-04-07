#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_sibling(traj, env_info, task_info):
    """
    Verify that the existing parent Robert Parr was linked to Dash Parr.
    
    Criteria:
    1. Database must show a link between Dash and Robert.
    2. No NEW parent records for 'Robert Parr' should be created (duplicate check).
    3. Robert should now be associated with at least 2 children (Violet and Dash).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract metrics
    link_exists = result.get("link_exists", False)
    duplicate_created = result.get("duplicate_created", False)
    robert_children_count = result.get("robert_children_count", 0)
    
    score = 0
    feedback = []

    # Criterion 1: Link Existence (40 pts)
    if link_exists:
        score += 40
        feedback.append("Success: Dash is linked to the correct parent record.")
    else:
        feedback.append("Fail: No link found between Dash and the existing Robert Parr record.")

    # Criterion 2: No Duplicates (30 pts)
    # This is crucial for the "Link Existing" requirement
    if not duplicate_created:
        score += 30
        feedback.append("Success: No duplicate parent records were created.")
    else:
        feedback.append("Fail: A new/duplicate 'Robert Parr' record was created instead of using the existing one.")

    # Criterion 3: Family Integrity (30 pts)
    # Robert should have at least 2 kids now (Violet + Dash)
    if robert_children_count >= 2:
        score += 30
        feedback.append(f"Success: Parent is now linked to {robert_children_count} students (Family intact).")
    else:
        # If link_exists is True, this should be True, but good sanity check
        if link_exists:
            feedback.append("Warning: Parent linked to Dash but lost link to Violet? (Unlikely but checked).")
        else:
            feedback.append("Fail: Parent is not linked to multiple children.")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }