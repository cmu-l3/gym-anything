#!/usr/bin/env python3
"""
Verifier for implement_product_documentation_field task.

Criteria:
1. Field 'field_user_manual' exists (storage & instance).
2. Field is enabled in the display configuration.
3. Correct data (URL and Title) is saved for the specified product.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_product_documentation_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', '')
    expected_title = metadata.get('expected_link_text', '')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Field Existence (30 pts)
    if result.get('field_storage_exists') and result.get('field_instance_exists'):
        score += 30
        feedback_parts.append("Field 'User Manual' created successfully")
    elif result.get('field_storage_exists'):
        score += 15
        feedback_parts.append("Field storage created, but instance missing")
    else:
        feedback_parts.append("Field 'User Manual' not found")

    # 2. Display Configuration (30 pts)
    # Requires the field to be in the display array
    if result.get('field_in_display'):
        score += 20
        feedback_parts.append("Field is enabled in display")
        
        if result.get('label_inline'):
            score += 10
            feedback_parts.append("Label set to Inline")
        else:
            feedback_parts.append("Label display is not set to Inline")
    else:
        feedback_parts.append("Field is hidden or not configured in 'Manage Display'")

    # 3. Data Verification (40 pts)
    if result.get('data_found'):
        actual_uri = result.get('actual_uri', '')
        actual_title = result.get('actual_title', '')
        
        # URL Check
        if actual_uri.strip() == expected_url.strip():
            score += 20
            feedback_parts.append("URL is correct")
        else:
            feedback_parts.append(f"URL mismatch. Got: {actual_uri}")
            
        # Title Check
        if actual_title.strip().lower() == expected_title.strip().lower():
            score += 20
            feedback_parts.append("Link text is correct")
        elif expected_title.strip().lower() in actual_title.strip().lower():
            score += 10 # Partial credit
            feedback_parts.append(f"Link text partial match. Got: {actual_title}")
        else:
            feedback_parts.append(f"Link text mismatch. Expected: '{expected_title}', Got: '{actual_title}'")
    else:
        feedback_parts.append("No data found for the Sony product")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }