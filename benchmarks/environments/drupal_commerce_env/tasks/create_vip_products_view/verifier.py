#!/usr/bin/env python3
"""
Verifier for Create VIP Products View task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_vip_products_view(traj, env_info, task_info):
    """
    Verifies the VIP view creation task.
    """
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
        
        # 1. Term Creation (10 pts)
        if result.get('term_exists', False):
            score += 10
            feedback_parts.append("VIP taxonomy term created")
        else:
            feedback_parts.append("VIP taxonomy term NOT found")

        # 2. Product Tagging (20 pts)
        tagged_count = 0
        if result.get('sony_tagged', False): tagged_count += 1
        if result.get('logi_tagged', False): tagged_count += 1
        
        if tagged_count == 2:
            score += 20
            feedback_parts.append("Both products tagged correctly")
        elif tagged_count == 1:
            score += 10
            feedback_parts.append("One product tagged correctly")
        else:
            feedback_parts.append("Products NOT tagged with VIP term")

        # 3. View Creation & Path (30 pts)
        if result.get('view_found', False):
            score += 10 # Base points for view existing with correct path
            if result.get('path_correct', False):
                 score += 10
                 feedback_parts.append("View created at /vip-products")
            else:
                 feedback_parts.append("View found but path incorrect")
        else:
            feedback_parts.append("No view found at /vip-products")

        # 4. Filters & Formatting (10 pts)
        if result.get('grid_format', False):
            score += 5
            feedback_parts.append("Grid format active")
        
        if result.get('filter_correct', False):
            score += 5
            feedback_parts.append("Category filter active")

        # 5. Access Control (30 pts)
        # This is the critical security component
        access_score = 0
        if result.get('access_restricted', False):
            access_score += 15
            feedback_parts.append("Role-based access configured")
        
        if result.get('anon_access_denied', False):
            access_score += 15
            feedback_parts.append("Anonymous access denied (HTTP 403)")
        elif result.get('http_code') == 200:
             feedback_parts.append("SECURITY FAIL: Anonymous users can access the page!")
        
        score += access_score

        passed = score >= 70 and result.get('access_restricted', False)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}