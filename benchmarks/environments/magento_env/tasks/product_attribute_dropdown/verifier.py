#!/usr/bin/env python3
"""Verifier for Product Attribute Dropdown task in Magento.

Task: Create 'material_origin' attribute (dropdown) with 5 specific options,
configure search/filter properties, and assign to Default attribute set.

Scored on multiple criteria. Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_product_attribute_dropdown(traj, env_info, task_info):
    """
    Verify product attribute creation and configuration.

    Criteria:
    1. Attribute 'material_origin' exists and was newly created (15 pts)
    2. Input type is 'select' (Dropdown) (10 pts)
    3. Options: All 5 specific options exist (20 pts)
    4. Attribute is not required (5 pts)
    5. Storefront Props: Searchable, Comparable, Filterable (30 pts total)
    6. Assigned to Default Attribute Set (20 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('attribute_code', 'material_origin')
    expected_options = set([o.lower() for o in metadata.get('required_options', [])])

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/product_attribute_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Attribute Exists (15 pts)
    found = result.get('attribute_found', False)
    code = result.get('attribute_code', '')
    newly_created = result.get('newly_created', False)

    if found and code == expected_code:
        if newly_created:
            score += 15
            feedback_parts.append("Attribute created successfully (15 pts)")
        else:
            # Penalize if it existed before task (anti-gaming), but allow partial if it matches
            score += 5
            feedback_parts.append("Attribute exists but was not created during this task (5 pts)")
    else:
        feedback_parts.append(f"Attribute '{expected_code}' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Input Type (10 pts)
    input_type = result.get('frontend_input', '')
    if input_type == 'select':
        score += 10
        feedback_parts.append("Input type is Dropdown (10 pts)")
    else:
        feedback_parts.append(f"Incorrect input type: {input_type} (expected Dropdown/select)")

    # 3. Options (20 pts)
    actual_options = result.get('options', [])
    actual_options_lower = set([o.lower() for o in actual_options])
    
    # Check intersection
    found_options = expected_options.intersection(actual_options_lower)
    missing_options = expected_options - actual_options_lower
    
    # 4 pts per correct option (max 20)
    opts_score = len(found_options) * 4
    score += opts_score
    
    if not missing_options:
        feedback_parts.append("All 5 options present (20 pts)")
    else:
        feedback_parts.append(f"Missing options: {', '.join(missing_options)} ({opts_score} pts)")

    # 4. Not Required (5 pts)
    is_required = str(result.get('is_required', '0'))
    if is_required == '0':
        score += 5
        feedback_parts.append("Attribute is not required (5 pts)")
    else:
        feedback_parts.append("Attribute set as Required (incorrect)")

    # 5. Storefront Properties (30 pts)
    props = result.get('storefront_properties', {})
    
    # Searchable (10)
    if str(props.get('is_searchable', '0')) == '1':
        score += 10
        feedback_parts.append("Searchable (10 pts)")
    else:
        feedback_parts.append("Not Searchable")
        
    # Comparable (10)
    if str(props.get('is_comparable', '0')) == '1':
        score += 10
        feedback_parts.append("Comparable (10 pts)")
    else:
        feedback_parts.append("Not Comparable")

    # Filterable in Layered Nav (10)
    # 1 = Filterable (with results), 2 = Filterable (no results)
    # We strictly asked for "Filterable (with results)" -> 1
    if str(props.get('is_filterable', '0')) == '1':
        score += 10
        feedback_parts.append("Filterable in Layered Nav (10 pts)")
    elif str(props.get('is_filterable', '0')) == '2':
        score += 5
        feedback_parts.append("Filterable (no results) selected - partial credit (5 pts)")
    else:
        feedback_parts.append("Not Filterable in Layered Nav")

    # 6. Assigned to Default Attribute Set (20 pts)
    is_assigned = result.get('is_assigned_to_default_set', False)
    if is_assigned:
        score += 20
        feedback_parts.append("Assigned to Default Attribute Set (20 pts)")
    else:
        feedback_parts.append("NOT assigned to Default Attribute Set (Missed critical step)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }