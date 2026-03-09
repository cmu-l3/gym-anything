#!/usr/bin/env python3
"""
Verifier for create_composite_hatch_style task.
"""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET

def verify_create_composite_hatch_style(traj, env_info, task_info):
    """
    Verify creation of composite hatch style and assignment to layer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('colors', {})
    expected_bg = expected_colors.get('background', '#E0E0E0').upper()
    expected_hatch = expected_colors.get('hatch', '#333333').upper()
    expected_border = expected_colors.get('border', '#000000').upper()
    expected_pattern = metadata.get('pattern', 'shape://slash')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Existence (20 pts)
    if result.get('style_exists'):
        score += 20
        feedback_parts.append("Style 'composite_hatch' created in 'ne' workspace")
    else:
        return {"passed": False, "score": 0, "feedback": "Style 'composite_hatch' NOT found in 'ne' workspace"}

    # 2. Layer Assignment (20 pts)
    if result.get('layer_assigned'):
        score += 20
        feedback_parts.append("Style correctly assigned as default to 'ne_countries'")
    else:
        feedback_parts.append(f"Layer 'ne_countries' has wrong default style: {result.get('assigned_style_name')}")

    # 3. WMS Render Test (10 pts)
    if result.get('render_success'):
        score += 10
        feedback_parts.append("WMS render check passed (valid PNG output)")
    else:
        feedback_parts.append("WMS render check failed (invalid style or error)")

    # 4. SLD Content Analysis (50 pts total)
    sld_content = result.get('sld_content', '')
    
    # Normalize SLD for simple string checking (robust against XML namespaces for simple checks)
    sld_norm = sld_content.upper()
    
    # Check Background Fill (15 pts)
    has_bg = False
    # Look for literal color inside a Fill or CssParameter
    if expected_bg in sld_norm:
        has_bg = True
        score += 15
        feedback_parts.append(f"Background color {expected_bg} found")
    else:
        feedback_parts.append(f"Background color {expected_bg} missing")

    # Check Hatch Pattern (25 pts)
    # Check for WellKnownName shape://slash
    pattern_norm = expected_pattern.upper()
    has_pattern_name = pattern_norm in sld_norm
    
    # Check for pattern color #333333
    has_pattern_color = expected_hatch in sld_norm
    
    if has_pattern_name and has_pattern_color:
        score += 25
        feedback_parts.append("Hatch pattern (shape://slash) and color found")
    elif has_pattern_name:
        score += 15
        feedback_parts.append("Hatch pattern found but color missing")
    elif has_pattern_color:
        # Ambiguous if only color found without pattern name, awarding minimal points
        score += 5
        feedback_parts.append("Hatch color found but pattern name missing")
    else:
        feedback_parts.append("Hatch pattern missing")

    # Check Border (10 pts)
    # Look for stroke #000000
    # Note: #000000 is common, so we need to ensure it's not just the pattern color (if they were same)
    # But here pattern is #333333 and bg is #E0E0E0, so #000000 must be border.
    if expected_border in sld_norm:
        score += 10
        feedback_parts.append("Border color #000000 found")
    else:
        feedback_parts.append("Border color #000000 missing")

    # Final check: symbolizer stacking
    # We expect multiple symbolizers. Since XML parsing can be brittle with namespaces in simple python,
    # we count occurrences of <PolygonSymbolizer> or <LineSymbolizer>.
    # A composite style usually has multiple symbolizers or multiple Fills.
    # We won't score explicitly on count to avoid penalizing valid optimizations, 
    # but the visual requirement implies complexity.
    
    passed = score >= 80  # Threshold requiring substantial correctness
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }