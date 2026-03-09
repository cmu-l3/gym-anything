#!/usr/bin/env python3
"""
Verifier for merge_duplicate_requests task.
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_requests(traj, env_info, task_info):
    """
    Verify that the duplicate requests were merged into the correct parent.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    
    # 1. Verify Parent Status (Must be active/Open) - 15 pts
    parent = result.get("parent", {})
    parent_status = parent.get("status", "").lower()
    
    # Acceptable open statuses
    open_statuses = ["open", "in progress", "on hold", "assigned"]
    
    if parent_status in open_statuses:
        score += 15
        feedback_parts.append(f"Parent request is active ({parent_status})")
    elif parent_status == "closed":
        feedback_parts.append("Parent request was incorrectly closed")
    else:
        feedback_parts.append(f"Parent status unknown or invalid ({parent_status})")

    # 2. Verify Correct Parent Selection - 15 pts
    # Setup script assigned "server" subject to parent ID. Result checks this.
    if parent.get("expected_subject_match"):
        score += 15
        feedback_parts.append("Correct parent request selected")
    else:
        feedback_parts.append("Wrong parent request selected (subject mismatch)")

    # 3. Verify Children Status (Must be Closed or Merged) - 15 pts each (45 total)
    children = result.get("children", [])
    merged_count = 0
    
    # Acceptable closed/merged statuses
    closed_statuses = ["closed", "resolved", "merged", "cancelled"]
    
    for child in children:
        c_status = child.get("status", "").lower()
        c_id = child.get("id")
        
        if c_status in closed_statuses:
            score += 15
            merged_count += 1
            feedback_parts.append(f"Child {c_id} is closed/merged")
        else:
            feedback_parts.append(f"Child {c_id} is still {c_status}")

    # 4. Verify Linkage (Database Relationship) - 25 pts
    # The export script checks WorkOrderToWorkOrder table
    # This proves they used the "Merge" function, not just manually closed tickets
    links_found = result.get("links_found", 0)
    expected_links = len(children)
    
    if links_found >= expected_links:
        score += 25
        feedback_parts.append("All requests successfully linked via merge")
    elif links_found > 0:
        score += int(25 * (links_found / expected_links))
        feedback_parts.append(f"Partial linkage found ({links_found}/{expected_links})")
    else:
        feedback_parts.append("No database merge links found (did you just close them manually?)")

    passed = (score >= 70) and (merged_count >= 2) and (links_found >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }