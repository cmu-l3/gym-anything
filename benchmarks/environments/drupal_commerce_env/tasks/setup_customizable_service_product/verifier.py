#!/usr/bin/env python3
"""
Verifier for setup_customizable_service_product task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_customizable_service_product(traj, env_info, task_info):
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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract configs
    oi_config = result.get("order_item_type_config", {})
    field_storage = result.get("field_storage_config", {})
    field_config = result.get("field_config", {})
    form_display = result.get("form_display_config", {})
    product_type_config = result.get("product_type_config", {})
    
    # 1. Verify Order Item Type 'service' exists (15 pts)
    # Drupal config IDs are usually keys in the json like "commerce_order_item_type.service"
    # But drush config:get returns the object content directly
    if oi_config and oi_config.get("id") == "service":
        score += 15
        feedback_parts.append("Order Item Type 'service' created.")
    else:
        feedback_parts.append("Order Item Type 'service' not found.")

    # 2. Verify Field exists (20 pts)
    # Check storage and config
    field_exists = False
    if field_storage and field_storage.get("type") == "string": # Text (plain) is 'string' type
        if field_config and field_config.get("bundle") == "service":
            field_exists = True
            
    if field_exists:
        score += 20
        # Check if required
        if field_config.get("required") is True:
            feedback_parts.append("Serial Number field created and is required.")
        else:
            feedback_parts.append("Serial Number field created (but not set to required).")
    else:
        feedback_parts.append("Serial Number field not found or not text type.")

    # 3. Verify Form Display 'add_to_cart' (25 pts)
    # This is critical. The field must be in the 'content' section, not 'hidden'.
    fd_content = form_display.get("content", {})
    field_name = "field_device_serial_number"
    
    if field_name in fd_content:
        # Check if region is content
        if fd_content[field_name].get("region") == "content":
            score += 25
            feedback_parts.append("Field is enabled in Add to Cart form display.")
        else:
            score += 10
            feedback_parts.append("Field is in form display but region is not 'content'.")
    else:
        feedback_parts.append("Field is NOT enabled in 'Add to Cart' form display (User won't see it).")

    # 4. Verify Product Type configuration (20 pts)
    # Must exist and link to 'service' order item type
    pt_id = product_type_config.get("id")
    pt_oi = product_type_config.get("orderItemType")
    
    if pt_id == "service":
        if pt_oi == "service":
            score += 20
            feedback_parts.append("Product Type 'service' correctly linked to Order Item Type.")
        else:
            score += 5
            feedback_parts.append(f"Product Type 'service' exists but links to wrong Order Item Type ('{pt_oi}').")
    else:
        feedback_parts.append("Product Type 'service' not found.")

    # 5. Verify Product creation (20 pts)
    product_found = result.get("product_found")
    product_type_actual = result.get("product_type_actual")
    
    if product_found is True or product_found == "true":
        if product_type_actual == "service":
            score += 20
            feedback_parts.append("Product 'iPhone Screen Repair' created with correct type.")
        else:
            score += 10
            feedback_parts.append(f"Product created but has wrong type ('{product_type_actual}').")
    else:
        feedback_parts.append("Product 'iPhone Screen Repair' not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }