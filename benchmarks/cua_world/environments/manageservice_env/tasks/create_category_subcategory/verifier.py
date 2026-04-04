#!/usr/bin/env python3
"""
Verifier for create_category_subcategory task.

Verifies:
1. Category 'Cloud Services' exists in the database.
2. Subcategories 'Provisioning', 'Performance Issues', 'Access Management' exist under that category.
3. Verification is done via persistent database state, preventing UI gaming.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_category_subcategory(traj, env_info, task_info):
    """
    Verify the creation of Incident Categories and Subcategories.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_category = metadata.get('target_category', 'Cloud Services')
    target_subcategories = metadata.get('target_subcategories', [
        "Provisioning", "Performance Issues", "Access Management"
    ])

    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    # 1. Verify Category Exists (40 points)
    category_exists = result.get('category_exists', False)
    found_name = result.get('category_name', '')
    
    if category_exists:
        score += 40
        feedback_parts.append(f"Category '{found_name}' created successfully.")
    else:
        feedback_parts.append(f"Category '{target_category}' NOT found.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Verify Subcategories (20 points each = 60 points total)
    found_subcats = result.get('subcategories_found', [])
    # Normalize for comparison
    found_subcats_norm = [s.lower().strip() for s in found_subcats]
    
    for target in target_subcategories:
        if target.lower().strip() in found_subcats_norm:
            score += 20
            feedback_parts.append(f"Subcategory '{target}' found.")
        else:
            feedback_parts.append(f"Subcategory '{target}' MISSING.")

    # 3. Anti-gaming check (Implicit)
    # The fact that we cleared the category in setup and found it now 
    # proves it was created during the task.
    # We can also check count increase as a sanity check.
    initial_count = int(result.get('initial_cat_count', 0))
    final_count = int(result.get('final_cat_count', 0))
    
    if final_count <= initial_count:
        # This might happen if they deleted another category, but usually suspicious.
        # We won't penalize hard if the specific records exist, but it's worth noting.
        logger.warning(f"Category count did not increase (Initial: {initial_count}, Final: {final_count})")

    # Final Calculation
    passed = (score >= 100)  # Require perfection for this configuration task
    
    # Adjust pass threshold if needed (e.g., allow 1 typo/missing subcat)
    # Task definition says "Pass Threshold: 60"
    pass_threshold = 60
    passed = (score >= pass_threshold)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }