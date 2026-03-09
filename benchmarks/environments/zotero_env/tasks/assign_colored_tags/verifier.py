#!/usr/bin/env python3
"""
Verifier for assign_colored_tags task.

Verifies:
1. 'tagColors' setting exists in Zotero DB.
2. Specific tags ('deep-learning', 'foundational', 'computer-vision', 'NLP') have assigned colors.
3. Tags are assigned to correct positions (1-4) based on array order.
4. Colors are visually distinct (hex values differ).
5. Tags still exist and have items attached (anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_colored_tags(traj, env_info, task_info):
    """
    Verify Zotero tag color assignments.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Expected config
    expected_order = ["deep-learning", "foundational", "computer-vision", "NLP"]
    
    # 1. Parse tagColors setting
    # Zotero stores this as a list of dicts: [{'name': 'tag', 'color': '#HEX'}, ...]
    # The index in the list corresponds to the position (0=Pos1, 1=Pos2, etc.)
    tag_colors = result.get('tag_colors_setting', [])
    
    if not isinstance(tag_colors, list):
        return {"passed": False, "score": 0, "feedback": "No tag colors configured (setting format invalid)."}
        
    if not tag_colors:
        return {"passed": False, "score": 0, "feedback": "No colored tags found."}

    # 2. Verify Assignments & Positions
    # We create a map of what was actually assigned
    assigned_map = {item.get('name'): {'color': item.get('color'), 'index': i} 
                   for i, item in enumerate(tag_colors)}
    
    colors_seen = set()
    correct_positions = 0
    assigned_tags_count = 0
    
    for i, expected_tag in enumerate(expected_order):
        expected_pos = i + 1
        
        if expected_tag in assigned_map:
            assigned_tags_count += 1
            data = assigned_map[expected_tag]
            actual_pos = data['index'] + 1
            color = data['color']
            
            # Score: Tag has color assigned (20 pts each)
            score += 20
            
            # Score: Position check (part of the 10 pts for ordering)
            if actual_pos == expected_pos:
                correct_positions += 1
            else:
                feedback_parts.append(f"Tag '{expected_tag}' at wrong position {actual_pos} (expected {expected_pos})")
            
            # Collect color for distinctness check
            if color:
                colors_seen.add(str(color).lower())
        else:
            feedback_parts.append(f"Tag '{expected_tag}' has no color assigned")

    # 3. Verify Distinct Colors (10 pts)
    # We need at least 3 distinct colors among the assigned ones
    if len(colors_seen) >= 3:
        score += 10
        feedback_parts.append(f"Used {len(colors_seen)} distinct colors")
    elif len(colors_seen) > 0:
        # Partial credit if they used 2 colors
        score += 5
        feedback_parts.append(f"Only {len(colors_seen)} distinct colors used (expected 3+)")
    else:
        feedback_parts.append("No valid colors found")

    # 4. Verify Ordering (10 pts)
    # All 4 must be in correct slots for full points here
    if correct_positions == 4:
        score += 10
        feedback_parts.append("All tags in correct positions")
    elif correct_positions > 0:
        partial = int(10 * correct_positions / 4)
        score += partial
        feedback_parts.append(f"{correct_positions}/4 tags in correct positions")

    # 5. Anti-gaming: Tags must still exist with items
    tag_stats = result.get('tag_stats', [])
    stats_map = {t['name']: t['count'] for t in tag_stats}
    
    for tag in expected_order:
        if stats_map.get(tag, 0) == 0:
            score = 0
            feedback_parts.append(f"CRITICAL: Tag '{tag}' was deleted or has no items! Anti-gaming penalty.")
            break

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }