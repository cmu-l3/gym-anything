#!/usr/bin/env python3
"""
Verifier for enable_product_reviews task.

Verifies:
1. 'product_review' comment type creation.
2. 'field_reviews' field addition to commerce_product.
3. Correct field configuration (linked to correct comment type).
4. Successful posting of a test review on the specific product.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_product_reviews(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. Verify Comment Type (20 pts)
    if result.get('comment_type_exists'):
        # Check label strictly? Description says label "Product Review", machine name "product_review"
        # The ID check is implicit in the `config:get comment.type.product_review` success.
        ct_config = result.get('comment_type_config', {})
        label = ct_config.get('label', '')
        if 'Product Review' in label:
            score += 20
            feedback.append("Comment Type 'Product Review' created successfully.")
        else:
            score += 15
            feedback.append(f"Comment Type created, but label '{label}' differs from 'Product Review'.")
    else:
        feedback.append("Comment Type 'product_review' NOT found.")

    # 2. Verify Field Storage (20 pts)
    # Checks if a field with the right name exists on commerce_product
    if result.get('field_storage_exists'):
        fs_config = result.get('field_storage_config', {})
        if fs_config.get('type') == 'comment':
            score += 20
            feedback.append("Field 'field_reviews' created on Product entity.")
        else:
            score += 5
            feedback.append("Field exists but is not of type 'comment'.")
    else:
        feedback.append("Field 'field_reviews' NOT found on Product entity.")

    # 3. Verify Field Configuration (20 pts)
    # Checks if the field is actually using the new comment type
    if result.get('field_instance_exists'):
        fi_config = result.get('field_instance_config', {})
        # Drupal stores the target comment type in settings.comment_type
        # Note: In Drush JSON export, it might be nested under 'settings'
        settings = fi_config.get('settings', {})
        linked_type = settings.get('comment_type', '')
        
        if linked_type == 'product_review':
            score += 20
            feedback.append("Field correctly configured to use 'product_review' comment type.")
        else:
            feedback.append(f"Field is using wrong comment type: '{linked_type}' (expected 'product_review').")
    else:
        feedback.append("Field instance configuration not found.")

    # 4. Verify Content Creation (Review Posted) (40 pts total)
    # Split into: Comment exists (20) and Linked correctly (20)
    
    comment_found = result.get('comment_found', False)
    timestamp = result.get('comment_timestamp', 0)
    start_time = result.get('task_start_time', 0)
    
    if comment_found:
        if timestamp >= start_time:
            score += 20
            feedback.append("Test review 'Amazing Quality' posted successfully.")
            
            # Check context
            if result.get('comment_on_correct_product') and result.get('comment_on_correct_field'):
                score += 20
                feedback.append("Review is correctly attached to the Sony product.")
            elif not result.get('comment_on_correct_product'):
                feedback.append("Review exists but is NOT attached to the correct product entity (check if you commented on a Node vs Product).")
            elif not result.get('comment_on_correct_field'):
                feedback.append("Review exists but is NOT in the 'field_reviews' field.")
        else:
            feedback.append("A review was found, but it appears to be from before the task started.")
    else:
        feedback.append("Test review 'Amazing Quality' NOT found on the target product.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }