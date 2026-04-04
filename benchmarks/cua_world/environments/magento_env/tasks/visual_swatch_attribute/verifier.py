#!/usr/bin/env python3
"""Verifier for Visual Swatch Attribute task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_visual_swatch_attribute(traj, env_info, task_info):
    """
    Verify that the 'finish_color' visual swatch attribute was created correctly.

    Criteria:
    1. Attribute 'finish_color' exists (20 pts)
    2. Input type is 'swatch_visual' (20 pts)
    3. Layered navigation is enabled (is_filterable=1 or 2) (15 pts)
    4. Three specific options exist with correct labels (10 pts each = 30 pts)
    5. Options have correct hex codes (15 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_options = metadata.get('options', [])

    try:
        # Copy result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/visual_swatch_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Check 1: Attribute Exists (20 pts)
    attr_found = result.get('attribute_found', False)
    if attr_found:
        score += 20
        feedback_parts.append("Attribute 'finish_color' created")
    else:
        feedback_parts.append("Attribute 'finish_color' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Input Type (20 pts)
    frontend_input = result.get('frontend_input', '')
    if frontend_input == 'swatch_visual':
        score += 20
        feedback_parts.append("Input type is Visual Swatch")
    else:
        feedback_parts.append(f"Incorrect input type: '{frontend_input}' (expected 'swatch_visual')")

    # Check 3: Layered Navigation (15 pts)
    # is_filterable: 1 = Filterable (with results), 2 = Filterable (no results)
    is_filterable = str(result.get('is_filterable', '0'))
    if is_filterable in ['1', '2']:
        score += 15
        feedback_parts.append("Layered Navigation enabled")
    else:
        feedback_parts.append("Layered Navigation NOT enabled")

    # Check 4 & 5: Options and Hex Codes
    created_options = result.get('options', [])
    
    # Helper to normalize hex for comparison (upper case, with #)
    def normalize_hex(h):
        if not h: return ""
        h = h.strip().upper()
        if not h.startswith('#'):
            h = '#' + h
        return h

    options_score = 0
    hex_score = 0
    matched_labels = []
    matched_hexes = []

    for expected in expected_options:
        exp_label = expected['label'].lower()
        exp_hex = normalize_hex(expected['hex'])
        
        # Find matching option by label
        match = next((o for o in created_options if o.get('label', '').lower() == exp_label), None)
        
        if match:
            options_score += 10
            matched_labels.append(expected['label'])
            
            # Check hex
            got_hex = normalize_hex(match.get('hex', ''))
            # Allow minor differences (e.g. stripped #) or exact match
            if got_hex == exp_hex:
                hex_score += 5
                matched_hexes.append(expected['hex'])
            else:
                feedback_parts.append(f"Hex for {expected['label']} incorrect (expected {exp_hex}, got {got_hex})")
        else:
            feedback_parts.append(f"Option '{expected['label']}' missing")

    # Cap option score at 30 (3 options * 10)
    score += min(options_score, 30)
    if options_score >= 30:
        feedback_parts.append("All option labels correct")

    # Cap hex score at 15 (3 options * 5)
    score += min(hex_score, 15)
    if hex_score >= 15:
        feedback_parts.append("All hex codes correct")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }