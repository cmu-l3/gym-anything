#!/usr/bin/env python3
"""
Verifier for implement_curated_cross_sells task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_curated_cross_sells(traj, env_info, task_info):
    """
    Verify the implementation of curated cross-sells.
    
    Criteria:
    1. Field 'field_related_accessories' exists on commerce_product (30 pts)
       - Must be entity_reference
       - Must be unlimited cardinality (-1)
    2. Display is configured correctly (35 pts)
       - Field is visible
       - Type is 'entity_reference_entity_view' (Rendered entity)
       - View mode is 'teaser'
    3. Data is curated correctly (35 pts)
       - MacBook Pro is linked to Logitech Mouse and Sony Headphones
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Verify Field Creation (30 pts)
    has_field = result.get('has_field', False)
    field_type = result.get('field_type', '')
    cardinality = str(result.get('cardinality', ''))
    
    if has_field:
        if field_type == 'entity_reference':
            score += 15
            feedback_parts.append("Field created with correct type.")
        else:
            score += 5
            feedback_parts.append(f"Field created but wrong type: {field_type}")
            
        if cardinality == '-1':
            score += 15
            feedback_parts.append("Field has correct unlimited cardinality.")
        else:
            feedback_parts.append(f"Field cardinality incorrect: {cardinality}")
    else:
        feedback_parts.append("Field 'field_related_accessories' not found.")

    # 2. Verify Display Configuration (35 pts)
    display_visible = result.get('display_visible', False)
    display_type = result.get('display_type', '')
    view_mode = result.get('view_mode', '')
    
    if display_visible:
        score += 10
        feedback_parts.append("Field is visible in display.")
        
        # Check format: Rendered entity (entity_reference_entity_view)
        if display_type == 'entity_reference_entity_view':
            score += 15
            feedback_parts.append("Display format is 'Rendered entity'.")
        else:
            feedback_parts.append(f"Display format incorrect: {display_type} (expected Rendered entity).")
            
        # Check view mode: Teaser
        if view_mode == 'teaser':
            score += 10
            feedback_parts.append("View mode is 'Teaser'.")
        else:
            feedback_parts.append(f"View mode incorrect: {view_mode} (expected Teaser).")
    else:
        feedback_parts.append("Field is not enabled in the Default display.")

    # 3. Verify Content Curation (35 pts)
    associations_correct = result.get('associations_correct', False)
    linked_ids = result.get('linked_ids', [])
    
    if associations_correct:
        score += 35
        feedback_parts.append("MacBook Pro correctly linked to both accessories.")
    else:
        # Partial credit?
        if len(linked_ids) > 0:
            score += 10
            feedback_parts.append(f"Found {len(linked_ids)} linked items, but not the specific required pair.")
        else:
            feedback_parts.append("No accessories linked to MacBook Pro.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }