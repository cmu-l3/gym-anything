#!/usr/bin/env python3
"""
Verifier for Bulk Update Requests task.

Criteria:
1. All 5 target requests must be assigned to "Clinical IT Support" (30 pts)
2. All 5 target requests must be Category "Medical Hardware" (30 pts)
3. All 5 target requests must be Subcategory "WOW Cart" (20 pts)
4. Updates should have occurred simultaneously (bulk action) (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    requests_data = result.get("requests", [])
    if not requests_data:
        return {"passed": False, "score": 0, "feedback": "No request data found for verification."}

    # Scoring
    score = 0
    feedback_parts = []
    
    # Constants from metadata
    EXPECTED_GROUP = "Clinical IT Support"
    EXPECTED_CAT = "Medical Hardware"
    EXPECTED_SUBCAT = "WOW Cart"

    correct_groups = 0
    correct_cats = 0
    correct_subcats = 0
    total_reqs = len(requests_data)

    for req in requests_data:
        # Check Group (case insensitive safe check)
        if req.get("group") and req["group"].lower() == EXPECTED_GROUP.lower():
            correct_groups += 1
        
        # Check Category
        if req.get("category") and req["category"].lower() == EXPECTED_CAT.lower():
            correct_cats += 1
            
        # Check Subcategory
        if req.get("subcategory") and req["subcategory"].lower() == EXPECTED_SUBCAT.lower():
            correct_subcats += 1

    # Calculate points
    # Group: 30 pts max (6 per req)
    score += (correct_groups / total_reqs) * 30
    
    # Category: 30 pts max (6 per req)
    score += (correct_cats / total_reqs) * 30
    
    # Subcategory: 20 pts max (4 per req)
    score += (correct_subcats / total_reqs) * 20

    feedback_parts.append(f"{correct_groups}/{total_reqs} groups correct")
    feedback_parts.append(f"{correct_cats}/{total_reqs} categories correct")
    feedback_parts.append(f"{correct_subcats}/{total_reqs} subcategories correct")

    # Bulk Action Verification (20 pts)
    # Check if timestamps were close together
    bulk_detected = result.get("bulk_detected", False)
    time_spread = result.get("time_spread_seconds", 999)

    if bulk_detected:
        score += 20
        feedback_parts.append("Bulk action confirmed (simultaneous updates)")
    else:
        feedback_parts.append(f"Bulk action NOT detected (spread: {time_spread:.1f}s)")
        # Partial credit if manually done correct but slow? No, instructions said Bulk Update.
        # But we'll leave it as strict 0 for this component to enforce efficiency.

    final_score = int(score)
    passed = final_score >= 80

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }