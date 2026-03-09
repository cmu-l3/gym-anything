#!/usr/bin/env python3
"""Verifier for Product Page Design Override task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_product_page_design_override(traj, env_info, task_info):
    """
    Verify that the product layout and options container were updated correctly.

    Criteria:
    1. Product LAPTOP-001 found (10 pts)
    2. Layout updated to '1column' (50 pts)
    3. Options container updated to 'container1' (Product Info Column) (40 pts)
    4. Anti-gaming: Check if other products were affected (Penalty)

    Pass threshold: 90 pts (Must get both settings correct)
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_layout = metadata.get('expected_layout', '1column')
    expected_container = metadata.get('expected_container', 'container1')

    try:
        # Copy result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_fn("/tmp/design_override_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Criterion 1: Product Found
        if result.get('product_found', False):
            score += 10
            feedback_parts.append("Product LAPTOP-001 found (10 pts)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Product LAPTOP-001 not found in database."
            }

        # Criterion 2: Layout Check
        current_layout = result.get('current_layout', '').strip()
        if current_layout == expected_layout:
            score += 50
            feedback_parts.append("Layout correctly set to '1 column' (50 pts)")
        else:
            feedback_parts.append(f"Layout incorrect: expected '{expected_layout}', got '{current_layout}'")

        # Criterion 3: Container Check
        current_container = result.get('current_container', '').strip()
        # 'container1' corresponds to "Product Info Column" in Magento admin
        if current_container == expected_container:
            score += 40
            feedback_parts.append("Options container correctly set to 'Product Info Column' (40 pts)")
        else:
            feedback_parts.append(f"Options container incorrect: expected '{expected_container}' (Product Info Column), got '{current_container}'")

        # Anti-gaming Check
        other_layout = result.get('other_product_layout', '')
        if other_layout == expected_layout:
            # If the control product also has the new layout, user likely applied a global change or mass update
            score -= 20
            feedback_parts.append("PENALTY: Other products were also changed. Task required changing ONLY LAPTOP-001 (-20 pts)")

        passed = score >= 90

        return {
            "passed": passed,
            "score": max(0, score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }