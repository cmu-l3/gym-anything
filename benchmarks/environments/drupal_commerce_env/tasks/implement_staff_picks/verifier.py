#!/usr/bin/env python3
"""
Verifier for Implement Staff Picks task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_staff_picks(traj, env_info, task_info):
    """
    Verifies the Staff Picks task based on:
    1. Schema: Field 'field_staff_pick' exists on Commerce Product.
    2. Data: Specific products have this field set to True.
    3. Config: A View exists with filter on this field.
    4. Config: A Block is placed in a region.
    5. Output: The homepage HTML contains the block title and product names.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Field Existence (20 pts)
    if result.get('field_exists', False):
        score += 20
        feedback_parts.append("Field 'field_staff_pick' created.")
    else:
        feedback_parts.append("Field 'field_staff_pick' NOT found.")

    # 2. Content Tagging (20 pts)
    # 10 pts for Sony, 10 pts for Logitech
    tags_score = 0
    if result.get('sony_tagged', False):
        tags_score += 10
    if result.get('logi_tagged', False):
        tags_score += 10
    
    # Penalty for false positives (tagging random stuff)
    false_positives = int(result.get('false_positives', 0))
    if false_positives > 0:
        tags_score = max(0, tags_score - 5)
        feedback_parts.append(f"{false_positives} incorrect products also tagged.")
    
    score += tags_score
    if tags_score == 20:
        feedback_parts.append("Correct products tagged.")
    elif tags_score > 0:
        feedback_parts.append("Some products tagged correctly.")
    else:
        feedback_parts.append("No correct products tagged.")

    # 3. View Creation (25 pts)
    view_score = 0
    if result.get('view_exists', False):
        view_score += 10
        if result.get('view_has_filter', False):
            view_score += 10
        if result.get('view_display_block', False):
            view_score += 5
        feedback_parts.append("View 'Staff Picks' created.")
    else:
        feedback_parts.append("View 'Staff Picks' NOT found.")
    score += view_score

    # 4. Block Placement (15 pts)
    if result.get('block_placed', False):
        score += 15
        feedback_parts.append(f"Block placed in region.")
    else:
        feedback_parts.append("Block NOT placed in any active region.")

    # 5. Frontend Visibility (20 pts)
    # Check if we can actually see it on the homepage
    html_score = 0
    if result.get('html_contains_title', False):
        html_score += 5
    if result.get('html_contains_sony', False):
        html_score += 7.5
    if result.get('html_contains_logi', False):
        html_score += 7.5
    
    score += html_score
    if html_score == 20:
        feedback_parts.append("Staff Picks block visible on homepage with products.")
    elif html_score > 0:
        feedback_parts.append("Staff Picks block partially visible (missing items?).")
    else:
        feedback_parts.append("Staff Picks block NOT visible on homepage.")

    # Pass Threshold
    passed = score >= 70 and result.get('field_exists', False) and result.get('view_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }