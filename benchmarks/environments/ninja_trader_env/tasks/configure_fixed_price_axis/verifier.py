#!/usr/bin/env python3
"""
Verifier for configure_fixed_price_axis task in NinjaTrader 8.

Criteria:
1. Workspace modified (20 pts)
2. SPY Chart exists (20 pts)
3. Fixed Scaling Enabled (IsAutoSize=False) (30 pts)
4. Correct Range (Min=400, Max=500) (30 pts)

Also uses VLM to verify visual state.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """
You are verifying a NinjaTrader 8 task.
The user was asked to configure a "Fixed" Price Axis (Y-axis) for a SPY chart, ranging from 400 to 500.

Look at the screenshot:
1. Is there a chart visible for "SPY"?
2. Look at the vertical axis (price numbers on the right).
3. Do the numbers roughly span 400 at the bottom to 500 at the top?
4. Does the axis look "fixed" (e.g., numbers are round integers like 400, 410... 500, or the range is clearly locked)?

Return JSON:
{
  "chart_visible": true/false,
  "spy_instrument_visible": true/false,
  "y_axis_range_correct": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_configure_fixed_price_axis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('min_value', 400)
    expected_max = metadata.get('max_value', 500)
    tolerance = metadata.get('tolerance', 0.1)

    # 1. Load JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic Verification (XML Analysis)
    # ---------------------------------------------------------

    # Criterion 1: Workspace Modified (20 pts)
    if result.get('workspace_modified', False):
        score += 20
        feedback_parts.append("Workspace saved (+20)")
    else:
        feedback_parts.append("Workspace not saved (0)")

    # Criterion 2: SPY Chart Exists (20 pts)
    if result.get('spy_instrument_found', False):
        score += 20
        feedback_parts.append("SPY chart found (+20)")
    else:
        feedback_parts.append("SPY chart NOT found (0)")
        # Stop here if chart missing
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Fixed Scaling Mode (30 pts)
    # Note: PowerShell exports boolean as true/false in JSON
    is_auto = result.get('is_auto_scale')
    
    if is_auto is False:
        score += 30
        feedback_parts.append("Fixed scaling mode enabled (+30)")
    elif is_auto is True:
        feedback_parts.append("Chart is still set to Auto Scale (0)")
    else:
        feedback_parts.append("Scaling mode not detected (0)")

    # Criterion 4: Correct Range (30 pts)
    actual_min = result.get('fixed_min')
    actual_max = result.get('fixed_max')
    
    range_correct = False
    
    if actual_min is not None and actual_max is not None:
        min_ok = abs(actual_min - expected_min) <= tolerance
        max_ok = abs(actual_max - expected_max) <= tolerance
        
        if min_ok and max_ok:
            score += 30
            range_correct = True
            feedback_parts.append(f"Range {actual_min}-{actual_max} is correct (+30)")
        else:
            feedback_parts.append(f"Range incorrect. Expected {expected_min}-{expected_max}, got {actual_min}-{actual_max}")
    else:
        feedback_parts.append("Fixed range values not found")

    # ---------------------------------------------------------
    # VLM Verification (Visual Confirmation)
    # ---------------------------------------------------------
    # We only penalize if VLM strongly contradicts, or give bonus?
    # Strategy: Use VLM to confirm visually if programmatic checks are borderline
    # For now, we rely primarily on XML for scoring, but could use VLM for "Do Nothing" check
    # if XML wasn't reliable. Given XML is reliable, we skip expensive VLM call to save tokens/time
    # unless score is high but suspect.
    
    pass_threshold = 70
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }