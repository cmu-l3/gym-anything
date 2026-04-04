#!/usr/bin/env python3
"""
Verifier for setup_clearance_section task.

Criteria:
1. Field 'field_clearance' created on product.
2. Target products (Sony, Logitech) flagged as clearance.
3. View page /clearance exists (returns 200 OK).
4. View page displays target products.
5. View page filters out non-clearance products (Apple).
6. Menu link exists.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_clearance_section(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Helper to safely get boolean values
        def get_bool(key):
            val = result.get(key, False)
            if isinstance(val, str):
                return val.lower() == 'true'
            return bool(val)

        # 1. Field Creation (20 pts)
        field_exists = int(result.get('field_config_exists', 0)) > 0
        if field_exists:
            score += 20
            feedback_parts.append("Field 'field_clearance' created.")
        else:
            feedback_parts.append("Field 'field_clearance' NOT found.")

        # 2. Product Flagging (20 pts)
        sony = get_bool('sony_flagged')
        logi = get_bool('logi_flagged')
        apple = get_bool('apple_flagged')
        
        if sony and logi:
            score += 20
            feedback_parts.append("Target products flagged correctly.")
        elif sony or logi:
            score += 10
            feedback_parts.append("Only some target products flagged.")
        else:
            feedback_parts.append("Target products NOT flagged.")
            
        # 3. View/Page Existence (20 pts)
        path_check = int(result.get('path_exists_in_router', 0)) > 0
        http_status = int(result.get('http_status', 0))
        
        if path_check or http_status == 200:
            score += 20
            feedback_parts.append("Clearance page (/clearance) exists.")
        else:
            feedback_parts.append("Clearance page NOT found.")

        # 4. Content Verification (20 pts)
        content_sony = get_bool('content_has_sony')
        content_logi = get_bool('content_has_logi')
        
        if content_sony and content_logi:
            score += 20
            feedback_parts.append("Clearance page shows correct products.")
        elif content_sony or content_logi:
            score += 10
            feedback_parts.append("Clearance page missing some products.")
        else:
            feedback_parts.append("Clearance page empty or missing target products.")

        # 5. Filtering Verification (10 pts)
        content_apple = get_bool('content_exclude_apple')
        # We want apple to be FALSE (not in content) AND apple_flagged to be FALSE
        if not content_apple and not apple:
            score += 10
            feedback_parts.append("Filtering works (non-clearance items excluded).")
        elif content_apple:
            feedback_parts.append("Filtering failed: Non-clearance item found on page.")
            
        # 6. Menu Link (10 pts)
        menu_link = int(result.get('menu_link_exists', 0)) > 0 or int(result.get('menu_tree_exists', 0)) > 0
        if menu_link:
            score += 10
            feedback_parts.append("Menu link 'Clearance' exists.")
        else:
            feedback_parts.append("Menu link NOT found.")

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}