#!/usr/bin/env python3
"""
Verifier for configure_order_number_pattern task.

Checks:
1. A new number pattern exists (compared to baseline).
2. Pattern configuration matches requirements:
   - Label contains "Urban Electronics"
   - Plugin type is "yearly"
   - Pattern string contains "UE-" and a year token
   - Padding is 6
   - Target entity type is "commerce_order"
3. The "default" order type is assigned to use this new pattern.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_order_number_pattern(traj, env_info, task_info):
    """
    Verify the Drupal Commerce number pattern configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_label_part = metadata.get('expected_label_part', 'Urban Electronics')
    expected_prefix = metadata.get('expected_prefix', 'UE-')
    expected_padding = metadata.get('expected_padding', 6)
    
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
    
    # 1. Identify the new pattern
    patterns = result.get('patterns', {})
    initial_list = result.get('initial_patterns_list', [])
    
    # Clean up initial list (drush output might be a list of strings "config.name")
    # We want just the ID part after the last dot
    initial_ids = set()
    for item in initial_list:
        if isinstance(item, str) and item.startswith('commerce_number_pattern.commerce_number_pattern.'):
            initial_ids.add(item.split('.')[-1])
    
    # Find candidate patterns (not in initial list OR matching label)
    candidate_pattern = None
    
    # Strategy: Look for specific label first
    for pid, pdata in patterns.items():
        if expected_label_part.lower() in pdata.get('label', '').lower():
            candidate_pattern = pdata
            break
            
    # Fallback: Look for any NEW pattern if label doesn't match perfectly
    if not candidate_pattern:
        for pid, pdata in patterns.items():
            if pid not in initial_ids and pid != 'order_default':
                candidate_pattern = pdata
                feedback_parts.append(f"Found new pattern '{pdata.get('label')}' (label mismatch)")
                break

    if not candidate_pattern:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new number pattern found with label containing 'Urban Electronics'"
        }

    # Criterion 1: New pattern exists (Implicitly passed if we are here)
    score += 15
    feedback_parts.append(f"Pattern found: {candidate_pattern.get('label')}")

    config = candidate_pattern.get('configuration', {})
    
    # Criterion 2: Pattern type is yearly (15 pts)
    plugin_id = candidate_pattern.get('plugin_id', '')
    if plugin_id == 'yearly':
        score += 15
        feedback_parts.append("Type is Yearly")
    else:
        feedback_parts.append(f"Wrong type: {plugin_id} (expected yearly)")

    # Criterion 3: Pattern includes "UE-" prefix (15 pts)
    pattern_str = config.get('pattern', '')
    if expected_prefix in pattern_str:
        score += 15
        feedback_parts.append(f"Prefix '{expected_prefix}' found")
    else:
        feedback_parts.append(f"Prefix '{expected_prefix}' missing from '{pattern_str}'")

    # Criterion 4: Pattern includes year token (15 pts)
    # Common Drupal tokens for year: [date:custom:Y], [current-date:custom:Y], [date:Y], {year}
    # We use a broad regex to catch likely year tokens
    year_token_regex = r"\[.*date.*:.*Y.*\]|\{.*year.*\}"
    if re.search(year_token_regex, pattern_str, re.IGNORECASE):
        score += 15
        feedback_parts.append("Year token found")
    else:
        feedback_parts.append(f"Year token missing in '{pattern_str}'")

    # Criterion 5: Padding is 6 (10 pts)
    actual_padding = config.get('padding')
    try:
        if int(actual_padding) == expected_padding:
            score += 10
            feedback_parts.append("Padding is 6")
        else:
            feedback_parts.append(f"Wrong padding: {actual_padding}")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid padding value: {actual_padding}")

    # Criterion 6: Target entity type is commerce_order (10 pts)
    target_type = candidate_pattern.get('target_entity_type', '')
    if target_type == 'commerce_order':
        score += 10
        feedback_parts.append("Target is Order")
    else:
        feedback_parts.append(f"Wrong target: {target_type}")

    # Criterion 7: Default order type uses this pattern (20 pts)
    order_type_config = result.get('default_order_type', {})
    assigned_pattern_id = order_type_config.get('number_pattern_id')
    new_pattern_id = candidate_pattern.get('id')
    
    if assigned_pattern_id == new_pattern_id:
        score += 20
        feedback_parts.append("Assigned to Default order type")
    else:
        feedback_parts.append(f"Not assigned to Default order type (currently uses '{assigned_pattern_id}')")

    # Final result
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }