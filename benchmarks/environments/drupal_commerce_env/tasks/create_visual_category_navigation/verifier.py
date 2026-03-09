#!/usr/bin/env python3
"""
Verifier for create_visual_category_navigation task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_visual_category_navigation(traj, env_info, task_info):
    """
    Verify the visual category navigation task.
    
    Criteria:
    1. Image field added to vocabulary (20 pts)
    2. Images uploaded for all 3 terms (30 pts)
    3. View created with correct settings (Grid, Terms, Image field) (25 pts)
    4. Block placed in Content region (25 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []
    
    # 2. Check Field Creation (20 pts)
    field_storage = int(result.get('field_storage_exists', 0))
    field_instance = int(result.get('field_instance_exists', 0))
    
    if field_storage > 0 and field_instance > 0:
        score += 20
        feedback.append("Image field created successfully.")
    elif field_storage > 0:
        score += 10
        feedback.append("Field storage exists but not attached to vocabulary correctly.")
    else:
        feedback.append("Image field not found.")

    # 3. Check Image Population (30 pts, 10 per term)
    images_ok = 0
    if result.get('headphones_has_image') == 'true': images_ok += 1
    if result.get('keyboards_has_image') == 'true': images_ok += 1
    if result.get('monitors_has_image') == 'true': images_ok += 1
    
    image_score = images_ok * 10
    score += image_score
    feedback.append(f"Images assigned to {images_ok}/3 terms.")

    # 4. Check View Creation (25 pts)
    view_exists = int(result.get('view_exists', 0))
    is_grid = result.get('view_is_grid') == 'true'
    shows_terms = result.get('view_shows_terms') == 'true'
    
    if view_exists > 0:
        view_score = 10
        if is_grid: view_score += 10
        if shows_terms: view_score += 5
        score += view_score
        feedback.append(f"View created (Grid: {is_grid}, Terms: {shows_terms}).")
    else:
        feedback.append("Category Grid view not found.")

    # 5. Check Block Placement (25 pts)
    block_placed = int(result.get('block_placed', 0))
    in_content = result.get('block_in_content') == 'true'
    
    if block_placed > 0:
        if in_content:
            score += 25
            feedback.append("Block placed in Content region.")
        else:
            score += 15
            feedback.append("Block placed, but region might be incorrect (expected 'content').")
    else:
        feedback.append("View block not placed on site.")

    # 6. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }