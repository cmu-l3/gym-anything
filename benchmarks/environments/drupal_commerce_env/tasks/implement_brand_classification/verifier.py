#!/usr/bin/env python3
"""
Verifier for implement_brand_classification task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_brand_classification(traj, env_info, task_info):
    """
    Verify the Brand Classification implementation.
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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Vocabulary Check (10 pts)
    if result.get('vocab_exists'):
        score += 10
        feedback_parts.append("'Brands' vocabulary created")
    else:
        feedback_parts.append("'Brands' vocabulary NOT found")

    # 2. Terms Check (10 pts - 3.33 each approx)
    terms_count = int(result.get('terms_found_count', 0))
    if terms_count >= 3:
        score += 10
        feedback_parts.append("All brand terms created")
    elif terms_count > 0:
        score += (terms_count * 3)
        feedback_parts.append(f"Only {terms_count}/3 terms created")
    else:
        feedback_parts.append("No brand terms found")

    # 3. Field Config (20 pts)
    if result.get('field_storage_exists') and result.get('field_instance_exists'):
        score += 10
        feedback_parts.append("Field 'field_brand' created")
        
        # Check specific settings
        if result.get('field_cardinality') == "1":
            score += 5
        else:
            feedback_parts.append("Cardinality is not 1")
            
        if result.get('field_target_type') == "taxonomy_term":
            score += 5
        else:
            feedback_parts.append("Field target type is not taxonomy_term")
    else:
        feedback_parts.append("Field 'field_brand' NOT found on Product")

    # 4. Displays (20 pts)
    if result.get('form_display_configured'):
        score += 10
        feedback_parts.append("Form display configured")
    else:
        feedback_parts.append("Form display NOT configured")

    if result.get('view_display_configured'):
        score += 10
        feedback_parts.append("View display configured")
    else:
        feedback_parts.append("View display NOT configured")

    # 5. Data Assignment (30 pts)
    if result.get('sony_tagged'):
        score += 15
        feedback_parts.append("Sony headphones tagged correctly")
    else:
        feedback_parts.append("Sony headphones NOT tagged with 'Sony'")

    if result.get('logitech_tagged'):
        score += 15
        feedback_parts.append("Logitech mouse tagged correctly")
    else:
        feedback_parts.append("Logitech mouse NOT tagged with 'Logitech'")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }