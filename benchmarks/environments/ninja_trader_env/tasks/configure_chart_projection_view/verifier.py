#!/usr/bin/env python3
"""
Verifier for configure_chart_projection_view task in NinjaTrader 8.

Checks:
1. Workspace file modified (10 pts)
2. Chart with SPY created (10 pts)
3. Right side margin set to 250 (25 pts)
4. Axis scaling set to Fixed with correct range (25 pts)
5. Bar spacing set to 15 (Zoomed) (15 pts)
6. Vertical grid lines hidden (15 pts)

Total: 100 points
Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_chart_projection_view(traj, env_info, task_info):
    """
    Verify the projection chart configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_margin = metadata.get('expected_right_margin', 250)
    expected_spacing = metadata.get('expected_bar_spacing', 15)
    spacing_tolerance = metadata.get('bar_spacing_tolerance', 2)
    expected_min = metadata.get('scale_min', 350)
    expected_max = metadata.get('scale_max', 550)
    scale_tolerance = metadata.get('scale_tolerance', 5)

    # Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The PowerShell script saves to a Windows temp path, but copy_from_env
        # typically handles the container path mapping.
        # If running on Windows container, path is C:\Users\Docker\AppData\Local\Temp\task_result.json
        # We try the standard temp location defined in the export script.
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Workspace Modified (10 pts)
    if result.get('workspace_modified') and result.get('timestamp_valid'):
        score += 10
        feedback_parts.append("Workspace saved")
    else:
        feedback_parts.append("Workspace not modified/saved")

    # Criterion 2: SPY Chart Exists (10 pts)
    if result.get('has_spy'):
        score += 10
        feedback_parts.append("SPY chart found")
    else:
        feedback_parts.append("SPY chart NOT found")
        # If no chart, other checks likely fail, but we check anyway
    
    # Criterion 3: Right Margin (25 pts)
    margin = result.get('right_margin', -1)
    if margin == expected_margin:
        score += 25
        feedback_parts.append(f"Right margin correct ({margin}px)")
    else:
        feedback_parts.append(f"Right margin incorrect (found: {margin}, expected: {expected_margin})")

    # Criterion 4: Fixed Scaling (25 pts)
    is_fixed = result.get('scale_fixed', False)
    val_min = result.get('scale_min', 0)
    val_max = result.get('scale_max', 0)
    
    scale_score = 0
    if is_fixed:
        scale_score += 10
        if abs(val_min - expected_min) <= scale_tolerance and abs(val_max - expected_max) <= scale_tolerance:
            scale_score += 15
            feedback_parts.append(f"Fixed scaling correct ({val_min}-{val_max})")
        else:
            feedback_parts.append(f"Fixed scaling enabled but range wrong ({val_min}-{val_max})")
    else:
        feedback_parts.append("Scaling not set to Fixed")
    score += scale_score

    # Criterion 5: Bar Spacing (15 pts)
    spacing = result.get('bar_spacing', -1)
    if abs(spacing - expected_spacing) <= spacing_tolerance:
        score += 15
        feedback_parts.append(f"Bar spacing correct ({spacing})")
    else:
        feedback_parts.append(f"Bar spacing incorrect (found: {spacing})")

    # Criterion 6: Grid Lines (15 pts)
    if result.get('grid_vertical_hidden'):
        score += 15
        feedback_parts.append("Vertical grid hidden")
    else:
        feedback_parts.append("Vertical grid visible")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }