#!/usr/bin/env python3
"""
Verifier for assign_colored_tag task.

Verification Logic:
1. Tag "Landmark Decision" must exist in the database.
2. The tag must have a color assigned (found in settings tables).
3. The tag must be applied to exactly the 3 specified cases.
4. The tag must NOT be applied to other items.

Scoring:
- Tag exists: 10 pts
- Color assigned: 20 pts
- Correct items tagged: 20 pts each (60 pts total)
- Precision (no extras): 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_colored_tag(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_tag = metadata.get('target_tag_name', 'Landmark Decision')
    target_cases = metadata.get('target_cases', [])

    # Get result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Database error: {result['error']}"
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Tag Existence (10 pts)
    if result.get('tag_found'):
        score += 10
        feedback_parts.append(f"Tag '{target_tag}' created (+10)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Tag '{target_tag}' not found in library.",
            "details": result
        }

    # 2. Check Color Assignment (20 pts)
    # The export script checks raw setting strings for the tag name
    if result.get('tag_color_assigned'):
        score += 20
        feedback_parts.append("Color assigned to tag (+20)")
    else:
        feedback_parts.append("No display color assigned to tag")

    # 3. Check Tagged Items (60 pts max)
    tagged_items_titles = result.get('tagged_items', [])
    # Normalize for case-insensitive matching
    tagged_items_lower = [t.lower() for t in tagged_items_titles]
    
    correct_count = 0
    for case in target_cases:
        # Check if any tagged item contains the case name
        # We use 'in' because titles might be "Brown v. Board of Education, 347 U.S. 483" vs just "Brown..."
        found = False
        for title in tagged_items_lower:
            if case.lower() in title:
                found = True
                break
        
        if found:
            score += 20
            correct_count += 1
            feedback_parts.append(f"Correctly tagged '{case}' (+20)")
        else:
            feedback_parts.append(f"Missed tagging '{case}'")

    # 4. Check Precision (10 pts)
    # Should only tag the 3 targets. 
    total_tagged = result.get('total_tagged_count', 0)
    
    # If we tagged exactly 3 and they were the right ones
    if total_tagged == 3 and correct_count == 3:
        score += 10
        feedback_parts.append("Perfect precision - exactly 3 items tagged (+10)")
    elif total_tagged > 3:
        feedback_parts.append(f"Too many items tagged ({total_tagged}), expected 3")
    elif total_tagged < 3:
        # Already penalized by missing items above
        pass

    # Final Pass/Fail
    # Need at least 70 points (Tag exists + Color + 2/3 cases)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tagged_found": tagged_items_titles,
            "settings_found": bool(result.get('settings_dump'))
        }
    }