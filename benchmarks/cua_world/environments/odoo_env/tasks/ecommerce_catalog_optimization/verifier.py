#!/usr/bin/env python3
"""
Verifier for ecommerce_catalog_optimization task.
Checks if categories created, products assigned, visibility set, and relations configured.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_ecommerce_catalog_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"System error: {result['error']}"}

    score = 0
    feedback = []

    # 1. Category Check (20 pts)
    cat_id = result.get('category_id')
    if result.get('category_found') and cat_id:
        score += 20
        feedback.append("Category 'Sustainable Workspace' created (20/20).")
    else:
        feedback.append("Category 'Sustainable Workspace' NOT found (0/20).")
        # Critical failure path for other checks that rely on category assignment? 
        # We can still check other props, but assignment will fail.

    # 2. Main Product Configuration (60 pts)
    main = result.get('main_product', {})
    setup = result.get('setup', {})
    
    # Category Assignment (15 pts)
    if cat_id and cat_id in main.get('category_ids', []):
        score += 15
        feedback.append("Main product added to category (15/15).")
    else:
        feedback.append("Main product NOT in correct category (0/15).")

    # Published Status (15 pts)
    if main.get('is_published'):
        score += 15
        feedback.append("Main product published (15/15).")
    else:
        feedback.append("Main product NOT published (0/15).")

    # Upsell (Alternative) (15 pts)
    if setup.get('upsell_product_id') in main.get('alternative_ids', []):
        score += 15
        feedback.append("Upsell (Alternative) product configured (15/15).")
    else:
        feedback.append("Upsell (Alternative) product missing (0/15).")

    # Cross-sell (Accessory) (15 pts)
    if setup.get('cross_sell_product_id') in main.get('accessory_ids', []):
        score += 15
        feedback.append("Cross-sell (Accessory) product configured (15/15).")
    else:
        feedback.append("Cross-sell (Accessory) product missing (0/15).")

    # 3. Draft Product Configuration (20 pts)
    draft = result.get('draft_product', {})

    # Category Assignment (10 pts)
    if cat_id and cat_id in draft.get('category_ids', []):
        score += 10
        feedback.append("Draft product added to category (10/10).")
    else:
        feedback.append("Draft product NOT in correct category (0/10).")

    # Unpublished Status (10 pts)
    if not draft.get('is_published'):
        score += 10
        feedback.append("Draft product correctly unpublished (10/10).")
    else:
        feedback.append("Draft product IS published (should be hidden) (0/10).")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }