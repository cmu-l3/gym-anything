#!/usr/bin/env python3
"""
Verifier for Setup Point & Figure Chart task (NinjaTrader 8).

Verifies that the agent:
1. Created/Modified a workspace file.
2. Configured a Point & Figure chart for AAPL.
3. Set correct Box Size (2) and Reversal (3).
4. Added an SMA(20) indicator.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_point_and_figure_chart(traj, env_info, task_info):
    """
    Verify the Point & Figure chart setup based on workspace XML analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container/VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in export script was C:\tmp\task_result.json
        # The copy_from_env should handle the path mapping or absolute path
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Anti-Gaming / Work Done (10 pts)
    if result.get("workspace_modified", False):
        score += 10
        feedback_parts.append("Workspace modified (+10)")
    else:
        feedback_parts.append("No workspace changes detected (0)")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Agent did not save any workspace changes. Task requires saving the configuration."
        }

    # 2. Instrument AAPL (15 pts)
    if result.get("found_instrument", False):
        score += 15
        feedback_parts.append("AAPL instrument found (+15)")
    else:
        feedback_parts.append("AAPL instrument NOT found (0)")

    # 3. Bar Type Point & Figure (25 pts)
    if result.get("found_bar_type", False):
        score += 25
        feedback_parts.append("Point & Figure bar type correct (+25)")
        
        # 3a. Box Size (15 pts) - Only valid if P&F
        if result.get("found_box_size", False):
            score += 15
            feedback_parts.append("Box Size 2 correct (+15)")
        else:
            feedback_parts.append("Box Size incorrect or default (0)")
            
        # 3b. Reversal (15 pts) - Only valid if P&F
        if result.get("found_reversal", False):
            score += 15
            feedback_parts.append("Reversal 3 correct (+15)")
        else:
            feedback_parts.append("Reversal incorrect or default (0)")
            
    else:
        feedback_parts.append("Chart is NOT Point & Figure (0) - Box/Reversal checks skipped")

    # 4. SMA Indicator (20 pts)
    if result.get("found_indicator", False) and result.get("found_period", False):
        score += 20
        feedback_parts.append("SMA(20) indicator correct (+20)")
    elif result.get("found_indicator", False):
        score += 10
        feedback_parts.append("SMA indicator found but wrong period (+10)")
    else:
        feedback_parts.append("SMA indicator missing (0)")

    # Pass Threshold
    passed = score >= 70 and result.get("found_bar_type", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }