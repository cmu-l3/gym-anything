#!/usr/bin/env python3
"""
Verifier for personalize_my_page task.

Verifies that the user's "My Page" layout in Redmine matches the requested configuration:
- Top: Latest news
- Left: Calendar
- Right: Spent time
- No extra blocks
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_personalize_my_page(traj, env_info, task_info):
    """
    Verify the layout of the Redmine 'My Page'.
    Uses the exported JSON which contains the raw Ruby hash from the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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

    layout = result.get('layout_json', {})
    
    # Expected layout logic
    # The keys in the layout hash (top, left, right) contain lists of block names.
    # Block names in Redmine are typically: 'news', 'calendar', 'spent_time', 'issuesassignedtome', etc.
    
    score = 0
    feedback_parts = []
    
    # Check Top Zone for 'news'
    top_blocks = layout.get('top', [])
    if 'news' in top_blocks:
        score += 30
        feedback_parts.append("PASS: 'Latest news' in Top zone")
    else:
        feedback_parts.append("FAIL: 'Latest news' missing from Top zone")

    # Check Left Zone for 'calendar'
    left_blocks = layout.get('left', [])
    if 'calendar' in left_blocks:
        score += 30
        feedback_parts.append("PASS: 'Calendar' in Left zone")
    else:
        feedback_parts.append("FAIL: 'Calendar' missing from Left zone")

    # Check Right Zone for 'spent_time'
    right_blocks = layout.get('right', [])
    if 'spent_time' in right_blocks:
        score += 30
        feedback_parts.append("PASS: 'Spent time' in Right zone")
    else:
        feedback_parts.append("FAIL: 'Spent time' missing from Right zone")

    # Check for cleanliness (no extra blocks)
    # We collect all blocks found and compare to the expected set
    all_blocks = []
    all_blocks.extend(top_blocks)
    all_blocks.extend(left_blocks)
    all_blocks.extend(right_blocks)
    
    # Filter out nulls/empty strings if any
    all_blocks = [b for b in all_blocks if b]
    
    expected_set = {'news', 'calendar', 'spent_time'}
    found_set = set(all_blocks)
    
    extras = found_set - expected_set
    missing = expected_set - found_set
    
    if not extras and not missing:
        score += 10
        feedback_parts.append("PASS: Layout is clean (no extra blocks)")
    elif extras:
        feedback_parts.append(f"FAIL: Found extra blocks: {', '.join(extras)}")
    
    passed = (score >= 90) # Requires all 3 correct blocks. Cleanliness is optional for pass but needed for perfect score.
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }