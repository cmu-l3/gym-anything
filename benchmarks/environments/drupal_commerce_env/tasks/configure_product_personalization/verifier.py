#!/usr/bin/env python3
"""
Verifier for configure_product_personalization task.

Criteria:
1. Field Created (30pts): A text field related to 'engraving' exists on commerce_order_item.
2. Field Instance (20pts): The field is attached to the 'default' bundle.
3. Form Display (40pts): The field is enabled in the 'add_to_cart' form display.
4. Label Correct (10pts): The label contains 'Engraving'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_personalization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load main result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)

        # Load form display JSON if it exists
        form_display_data = {}
        if result.get('form_display_exists'):
            form_display_path = result.get('form_display_json_path')
            temp_display = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            try:
                copy_from_env(form_display_path, temp_display.name)
                with open(temp_display.name, 'r') as f:
                    form_display_data = json.load(f)
            except Exception as e:
                logger.warning(f"Failed to load form display JSON: {e}")
            finally:
                if os.path.exists(temp_display.name):
                    os.unlink(temp_display.name)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading verification data: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Verify Field Creation
    field_found = result.get('field_found', False)
    field_name = result.get('field_name', '')
    
    if field_found:
        score += 30
        feedback_parts.append(f"Field '{field_name}' created")
    else:
        return {"passed": False, "score": 0, "feedback": "No engraving field found on Order Item type"}

    # 2. Verify Field Instance
    if result.get('field_instance_exists', False):
        score += 20
        feedback_parts.append("Field instance attached to Default type")
    else:
        feedback_parts.append("Field storage exists but not attached to Default order item type")

    # 3. Verify Form Display (CRITICAL)
    # We check if the field is in the 'content' region of the add_to_cart display
    form_display_correct = False
    
    if result.get('form_display_exists', False) and form_display_data:
        content = form_display_data.get('content', {})
        if field_name in content:
            # Check if it's actually visible (region is content)
            region = content[field_name].get('region', '')
            if region == 'content':
                score += 40
                form_display_correct = True
                feedback_parts.append("Field correctly enabled in 'Add to Cart' form")
            else:
                score += 10
                feedback_parts.append(f"Field in form display but region is '{region}' (expected 'content')")
        else:
            feedback_parts.append("Field not found in 'Add to Cart' form display enabled fields")
    else:
        feedback_parts.append("'Add to Cart' form display not configured")

    # 4. Verify Label
    label = result.get('field_label', '')
    if "engraving" in label.lower():
        score += 10
        feedback_parts.append(f"Label correct: '{label}'")
    else:
        feedback_parts.append(f"Label '{label}' does not contain 'Engraving'")

    passed = score >= 70 and form_display_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }