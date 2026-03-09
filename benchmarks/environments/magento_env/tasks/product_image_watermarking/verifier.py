#!/usr/bin/env python3
"""Verifier for Product Image Watermarking task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_product_image_watermarking(traj, env_info, task_info):
    """
    Verify watermarking configuration.

    Criteria:
    1. Configuration saved to Main Website scope (scope='websites', id=1)
    2. Watermark image uploaded for Base, Small, and Thumbnail roles
    3. Opacity set to 20 for all roles
    4. Position set to 'center' for all roles
    5. Uploaded files actually exist on disk

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_opacity = metadata.get('expected_opacity', '20')
    expected_position = metadata.get('expected_position', 'center') # Note: Might be 'tile', 'stretch', 'center'

    try:
        # Copy result JSON
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/watermark_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # Check for wrong scope
    if result.get('wrong_scope_detected', False):
        feedback_parts.append("WARNING: Configuration found in Default Config (Global) instead of Main Website scope.")
        # We penalize but continue checking? Design doc says "Scope Correct" is 10 pts.
        # If it's in default, it fails the "Configuration Scope Correct" criterion.
    
    roles = ['base_image', 'small_image', 'thumbnail_image']
    role_names = {'base_image': 'Base', 'small_image': 'Small', 'thumbnail_image': 'Thumbnail'}
    
    # Track criteria fulfillment
    scope_correct = True # Assumed true unless we find empty values here but present elsewhere
    files_set = 0
    opacity_correct_count = 0
    position_correct_count = 0
    
    for role in roles:
        data = result.get(role, {})
        file_val = data.get('file', '')
        opacity_val = str(data.get('opacity', '')).strip()
        pos_val = str(data.get('position', '')).lower().strip()
        exists = data.get('file_exists_on_disk', False)
        
        lbl = role_names[role]
        
        # Check File
        if file_val and exists:
            files_set += 1
        elif file_val:
            feedback_parts.append(f"{lbl} image path set but file missing on disk")
        else:
            # If empty, check if we detected wrong scope earlier
            if result.get('wrong_scope_detected', False):
                scope_correct = False
            
        # Check Opacity
        if opacity_val == expected_opacity:
            opacity_correct_count += 1
        elif opacity_val:
             feedback_parts.append(f"{lbl} Opacity incorrect: {opacity_val} (expected {expected_opacity})")
             
        # Check Position
        # Position might be 'center' or '1' depending on Magento version/theme. 
        # UI usually sends 'center'.
        if pos_val == expected_position:
            position_correct_count += 1
        elif pos_val:
            feedback_parts.append(f"{lbl} Position incorrect: {pos_val} (expected {expected_position})")

    # Scoring
    
    # 1. Scope Correct (10 pts)
    # If we found settings in the correct scope (at least one file set), and didn't flag wrong scope as primary
    if files_set > 0 and scope_correct:
        score += 10
        feedback_parts.append("Configuration applied to correct scope (10 pts)")
    else:
        feedback_parts.append("Configuration missing or in wrong scope (Global/Default)")
        
    # 2. Files Set (10 pts each = 30 pts)
    # Actually design doc says 10 pts per role for "Watermark Set"
    if files_set == 3:
        score += 30
        feedback_parts.append("All 3 watermarks set (30 pts)")
    else:
        score += (files_set * 10)
        feedback_parts.append(f"{files_set}/3 watermarks set ({files_set*10} pts)")
        
    # 3. Opacity Correct (30 pts total, 10 each)
    if opacity_correct_count == 3:
        score += 30
        feedback_parts.append("Opacity correct for all images (30 pts)")
    else:
        score += (opacity_correct_count * 10)
        feedback_parts.append(f"Opacity correct for {opacity_correct_count}/3 images")
        
    # 4. Position Correct (30 pts total, 10 each)
    if position_correct_count == 3:
        score += 30
        feedback_parts.append("Position correct for all images (30 pts)")
    else:
        score += (position_correct_count * 10)
        feedback_parts.append(f"Position correct for {position_correct_count}/3 images")
        
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }