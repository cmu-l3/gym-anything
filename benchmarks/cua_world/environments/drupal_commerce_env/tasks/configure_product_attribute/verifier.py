#!/usr/bin/env python3
"""
Verifier for configure_product_attribute task.

Criteria:
1. Attribute 'Color' exists (15 pts)
2. Five specific values exist (10 pts each = 50 pts)
   - Midnight Black, Arctic White, Ocean Blue, Forest Green, Sunset Red
3. No extra values (10 pts)
4. Associated with 'Default' variation type (25 pts)

Pass Threshold: 70 points.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_attribute(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_values = set([v.lower() for v in metadata.get('expected_values', [])])
    
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
    
    # 1. Check Attribute Existence (15 pts)
    if result.get("attribute_found"):
        score += 15
        feedback_parts.append("Attribute 'Color' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Attribute 'Color' not found"}

    # 2. Check Values (50 pts total, 10 per value)
    found_values_raw = result.get("found_values", [])
    found_values_lower = [v.lower() for v in found_values_raw]
    
    matched_count = 0
    missing_values = []
    
    # Check each expected value
    # We defined expected_values as a set of lower case strings above
    original_expected = metadata.get('expected_values', [])
    
    for expected in original_expected:
        if expected.lower() in found_values_lower:
            score += 10
            matched_count += 1
        else:
            missing_values.append(expected)
            
    if matched_count == 5:
        feedback_parts.append("All 5 color values found")
    else:
        feedback_parts.append(f"Found {matched_count}/5 color values. Missing: {', '.join(missing_values)}")

    # 3. Check for Extras (10 pts)
    # The list should contain exactly 5 items
    if len(found_values_raw) == 5 and matched_count == 5:
        score += 10
        feedback_parts.append("Exactly 5 values present")
    elif len(found_values_raw) > 5:
        feedback_parts.append(f"Too many values found ({len(found_values_raw)})")
    elif len(found_values_raw) < 5:
        # Penalty handled by missing values check, but we don't give the 'exact match' bonus
        pass

    # 4. Check Association (25 pts)
    if result.get("variation_associated"):
        score += 25
        feedback_parts.append("Attribute correctly associated with 'Default' variation type")
    else:
        feedback_parts.append("Attribute NOT associated with 'Default' variation type")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }