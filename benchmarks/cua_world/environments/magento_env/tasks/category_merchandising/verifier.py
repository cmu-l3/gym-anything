#!/usr/bin/env python3
"""Verifier for Category Merchandising task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_category_merchandising(traj, env_info, task_info):
    """
    Verify that the category merchandising settings are correct.

    Criteria:
    1. Category 'Electronics' default sort order is set to 'position' (40 pts)
    2. Laptop (LAPTOP-001) position is 10 (20 pts)
    3. Smartphone (PHONE-001) position is 20 (20 pts)
    4. Headphones (HEADPHONES-001) position is 30 (20 pts)

    Pass threshold: 100 pts (All configuration steps required for correct visual order)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/merchandising_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        cat_found = result.get('category_found', False)
        if not cat_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Critical Error: 'Electronics' category not found in database."
            }

        # Criterion 1: Sort By Setting
        sort_setting = result.get('sort_by_setting', '').strip().lower()
        if sort_setting == 'position':
            score += 40
            feedback_parts.append("Category sort order set to 'Position' (40 pts)")
        else:
            feedback_parts.append(f"Sort order incorrect: expected 'position', got '{sort_setting}'")

        # Criterion 2, 3, 4: Product Positions
        positions = result.get('positions', {})
        
        # Laptop -> 10
        laptop_pos = positions.get('laptop', -1)
        if laptop_pos == 10:
            score += 20
            feedback_parts.append("Laptop position correct (10) (20 pts)")
        else:
            feedback_parts.append(f"Laptop position incorrect: expected 10, got {laptop_pos}")

        # Phone -> 20
        phone_pos = positions.get('phone', -1)
        if phone_pos == 20:
            score += 20
            feedback_parts.append("Smartphone position correct (20) (20 pts)")
        else:
            feedback_parts.append(f"Smartphone position incorrect: expected 20, got {phone_pos}")

        # Headphones -> 30
        headphones_pos = positions.get('headphones', -1)
        if headphones_pos == 30:
            score += 20
            feedback_parts.append("Headphones position correct (30) (20 pts)")
        else:
            feedback_parts.append(f"Headphones position incorrect: expected 30, got {headphones_pos}")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}