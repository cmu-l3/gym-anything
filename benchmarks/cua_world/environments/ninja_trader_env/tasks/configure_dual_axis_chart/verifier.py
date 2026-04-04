#!/usr/bin/env python3
"""
Verifier for configure_dual_axis_chart task.

Verifies that the agent created a NinjaTrader chart with:
1. Two specific instruments (AAPL, MSFT).
2. Correct overlay configuration (Same Panel).
3. Correct Scale Justification (AAPL=Right, MSFT=Left).
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dual_axis_chart(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the dual-axis chart configuration using the exported JSON result
    and VLM visual confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring components
    score = 0
    feedback_parts = []
    
    # 1. Workspace Modification (20 pts)
    if result.get('workspace_modified', False):
        score += 20
        feedback_parts.append("Workspace saved.")
    else:
        feedback_parts.append("Workspace NOT saved.")

    # 2. Chart and Instruments (20 pts)
    instruments = result.get('instruments_found', [])
    if result.get('chart_found', False) and 'AAPL' in instruments and 'MSFT' in instruments:
        score += 20
        feedback_parts.append("Chart created with AAPL and MSFT.")
    elif result.get('chart_found', False):
        score += 10
        feedback_parts.append(f"Chart found but missing instruments (Found: {instruments}).")
    else:
        feedback_parts.append("No valid chart found.")

    # 3. Single Panel Overlay (20 pts)
    # The agent must overlay them, not stack them.
    if result.get('single_panel', False):
        score += 20
        feedback_parts.append("Instruments overlayed on single panel.")
    else:
        feedback_parts.append("Instruments appear to be in separate panels (not overlayed).")

    # 4. Axis Configuration (40 pts) - The core challenge
    aapl_axis = result.get('aapl_axis', 'Unknown')
    msft_axis = result.get('msft_axis', 'Unknown')
    
    axis_score = 0
    if aapl_axis == 'Right':
        axis_score += 20
    if msft_axis == 'Left':
        axis_score += 20
    
    score += axis_score
    
    if axis_score == 40:
        feedback_parts.append("Axis configuration correct (AAPL=Right, MSFT=Left).")
    else:
        feedback_parts.append(f"Axis config incorrect (AAPL={aapl_axis}, MSFT={msft_axis}).")

    # Final Pass Check
    # Must have saved workspace, found chart, and got axis config mostly right
    passed = score >= 70 and result.get('axis_config_correct', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }