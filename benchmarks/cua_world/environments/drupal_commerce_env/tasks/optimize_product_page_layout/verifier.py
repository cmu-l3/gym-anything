#!/usr/bin/env python3
"""
Verifier for optimize_product_page_layout task.
Checks if the Product Variation display configuration has been updated correctly.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_optimize_product_page_layout(traj, env_info, task_info):
    """
    Verify that:
    1. SKU field is visible (in content region).
    2. Image style is set to 'large'.
    3. Configuration was actually modified.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. Check if Config Changed (Anti-gaming / Baseline)
    if result.get('config_changed'):
        score += 20
        feedback_parts.append("Configuration modified")
    else:
        feedback_parts.append("No configuration changes detected")

    # 2. Check SKU Visibility
    # "sku_visible" comes from checking isset($content['sku']) in the export script
    if result.get('sku_visible'):
        score += 40
        feedback_parts.append("SKU is visible")
    else:
        feedback_parts.append("SKU is still hidden")

    # 3. Check Image Style
    actual_style = result.get('image_style', '')
    if actual_style == 'large':
        score += 40
        feedback_parts.append("Image style set to Large")
    elif actual_style == 'medium':
        feedback_parts.append("Image style unchanged (Medium)")
    else:
        feedback_parts.append(f"Image style incorrect: {actual_style}")

    # Pass threshold: 80 points (Must have config changed + SKU visible + Image Large)
    # Actually, 20+40+40 = 100.
    # Partial credit allowed, but pass requires significant progress.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }