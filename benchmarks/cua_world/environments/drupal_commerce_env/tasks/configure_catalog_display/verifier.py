#!/usr/bin/env python3
"""
Verifier for Configure Catalog Display task in Drupal Commerce.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_catalog_display(traj, env_info, task_info):
    """
    Verify that the product and variation displays were configured correctly.
    
    Checks:
    1. Product Display: 'stores', 'uid', 'created' are in the 'hidden' list.
    2. Product Display: 'body' label is set to 'hidden'.
    3. Variation Display: 'images' field uses 'large' image style.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_hidden = metadata.get('expected_hidden_fields', ['stores', 'uid', 'created'])
    expected_body_label = metadata.get('expected_body_label', 'hidden')
    expected_image_style = metadata.get('expected_image_style', 'large')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        max_score = 100
        feedback_parts = []
        
        # 1. Check Product Display Configuration (45 points)
        prod_config = result.get('product_display', {})
        hidden_fields = prod_config.get('hidden', {})
        content_fields = prod_config.get('content', {})
        
        # Check hidden fields (30 pts - 10 per field)
        hidden_score = 0
        missing_hidden = []
        for field in expected_hidden:
            # Drush export might return hidden as a dict {field: true} or list [field]
            # Drupal 8+ usually exports 'hidden' as a dictionary keyed by field name
            if field in hidden_fields:
                hidden_score += 10
            else:
                missing_hidden.append(field)
        
        score += hidden_score
        if not missing_hidden:
            feedback_parts.append("All metadata fields hidden correctly")
        else:
            feedback_parts.append(f"Failed to hide fields: {', '.join(missing_hidden)}")
            
        # Check Body label (15 pts)
        body_config = content_fields.get('body', {})
        actual_label = body_config.get('label', 'above') # Default is usually above
        
        if actual_label == expected_body_label:
            score += 15
            feedback_parts.append("Body label hidden correctly")
        else:
            feedback_parts.append(f"Body label incorrect (expected '{expected_body_label}', got '{actual_label}')")

        # 2. Check Variation Display Configuration (45 points)
        var_config = result.get('variation_display', {})
        var_content = var_config.get('content', {})
        images_config = var_content.get('images', {})
        
        # Check image style (45 pts)
        # Structure is usually content -> images -> settings -> image_style
        actual_style = images_config.get('settings', {}).get('image_style', '')
        
        if actual_style == expected_image_style:
            score += 45
            feedback_parts.append(f"Image style set to '{expected_image_style}'")
        else:
            feedback_parts.append(f"Image style incorrect (expected '{expected_image_style}', got '{actual_style}')")

        # 3. Basic Validation (10 points)
        # Ensure we actually got valid config objects back
        if prod_config and var_config:
            score += 10
        else:
            feedback_parts.append("Failed to retrieve configuration from Drupal")

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}