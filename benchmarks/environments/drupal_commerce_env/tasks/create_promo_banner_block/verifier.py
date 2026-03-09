#!/usr/bin/env python3
"""
Verifier for create_promo_banner_block task in Drupal Commerce.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_promo_banner_block(traj, env_info, task_info):
    """
    Verify creation of Block Type, Fields, Content, and Placement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_coupon = metadata.get('expected_coupon_value', 'SUMMER20')

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
        
        # 1. Block Type (20 pts)
        if str(result.get('block_type_exists')).lower() == 'true':
            score += 20
            feedback_parts.append("Block type 'promo_banner' created")
        else:
            feedback_parts.append("Block type 'promo_banner' NOT found")

        # 2. Fields (20 pts)
        fields_ok = 0
        if str(result.get('field_link_exists')).lower() == 'true':
            fields_ok += 10
        if str(result.get('field_coupon_exists')).lower() == 'true':
            fields_ok += 10
        score += fields_ok
        if fields_ok == 20:
            feedback_parts.append("All fields created")
        elif fields_ok > 0:
            feedback_parts.append("Some fields missing")
        else:
            feedback_parts.append("Fields NOT found")

        # 3. Block Content (20 pts)
        if str(result.get('block_found')).lower() == 'true':
            score += 20
            feedback_parts.append("Block 'Summer Audio Sale' created")
        else:
            feedback_parts.append("Block 'Summer Audio Sale' NOT found")
            
        # 4. Content Data (20 pts)
        data_score = 0
        actual_coupon = str(result.get('coupon_value', '')).strip()
        actual_link = str(result.get('link_uri', ''))
        
        if actual_coupon == expected_coupon:
            data_score += 10
        elif actual_coupon:
            data_score += 5 # Partial credit if value exists but wrong
            feedback_parts.append(f"Coupon wrong: '{actual_coupon}'")
            
        if 'product' in actual_link or 'shop' in actual_link or '/products' in actual_link:
             data_score += 10
        elif actual_link:
             data_score += 5
             feedback_parts.append(f"Link wrong: '{actual_link}'")
             
        score += data_score
        if data_score == 20:
            feedback_parts.append("Block content correct")

        # 5. Placement (20 pts)
        if str(result.get('placement_found')).lower() == 'true':
            score += 20
            feedback_parts.append(f"Block placed in sidebar ({result.get('placement_region')})")
        else:
            feedback_parts.append("Block NOT placed in sidebar")
            
        passed = score >= 80
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}