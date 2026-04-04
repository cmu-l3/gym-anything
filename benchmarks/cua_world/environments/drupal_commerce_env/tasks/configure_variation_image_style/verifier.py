#!/usr/bin/env python3
"""
Verifier for configure_variation_image_style task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_variation_image_style(traj, env_info, task_info):
    """
    Verify the image style creation and application.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style = metadata.get('style_name', 'product_main_600')
    expected_width = metadata.get('width', 600)
    expected_height = metadata.get('height', 600)

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
    feedback_parts = []
    
    # 1. Image Style Exists (25 pts)
    if result.get('style_exists'):
        score += 25
        feedback_parts.append(f"Image style '{expected_style}' created")
    else:
        feedback_parts.append(f"Image style '{expected_style}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Correct Effect (25 pts)
    has_effect = result.get('has_scale_crop')
    width = int(result.get('width', 0))
    height = int(result.get('height', 0))
    
    if has_effect and width == expected_width and height == expected_height:
        score += 25
        feedback_parts.append(f"Scale and crop effect correct ({width}x{height})")
    else:
        feedback_parts.append(f"Effect incorrect (Found: scale_crop={has_effect}, {width}x{height})")
        # Partial credit if effect is right type but wrong dims
        if has_effect:
            score += 10

    # 3. Variation Display Configured (25 pts)
    # 4. Saved & Persisted (25 pts) - effectively checked by display_updated
    if result.get('display_updated') and result.get('used_style') == expected_style:
        score += 50
        feedback_parts.append("Product variation display updated successfully")
    else:
        feedback_parts.append("Product variation display NOT updated to use new style")
        if result.get('display_config_exists'):
            score += 10 # Config exists but maybe wrong style

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }