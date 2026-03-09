#!/usr/bin/env python3
"""
Verifier for configure_drawing_tool_alert task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Path where the PowerShell script saves the result inside the container
RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/configure_drawing_tool_alert_result.json"

def verify_configure_drawing_tool_alert(traj, env_info, task_info):
    """
    Verifies the agent correctly configured a horizontal line alert on SPY at 500.00.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task metadata
    metadata = task_info.get('metadata', {})
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task results. Did you save the workspace? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Modification (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace modified (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        return {"passed": False, "score": 0, "feedback": "Workspace not saved - no changes persisted."}

    # 2. Chart/Instrument Check (10 pts)
    if result.get('instrument_found', False):
        score += 10
        feedback_parts.append("SPY chart found (+10)")
    else:
        feedback_parts.append("SPY chart NOT found")

    # 3. Horizontal Line Exists (20 pts)
    if result.get('tool_found', False):
        score += 20
        feedback_parts.append("Horizontal Line found (+20)")
    else:
        feedback_parts.append("Horizontal Line NOT found")

    # 4. Price Level Accuracy (20 pts)
    if result.get('price_correct', False):
        score += 20
        feedback_parts.append("Price level 500.00 correct (+20)")
    else:
        feedback_parts.append("Price level incorrect (expected 500.00)")

    # 5. Alert Enabled (25 pts)
    if result.get('alert_enabled', False):
        score += 25
        feedback_parts.append("Alert enabled (+25)")
    else:
        feedback_parts.append("Alert NOT enabled")

    # 6. Alert Condition (15 pts)
    if result.get('condition_correct', False):
        score += 15
        feedback_parts.append("Condition 'CrossAbove' correct (+15)")
    else:
        feedback_parts.append("Condition incorrect (expected CrossAbove)")

    # Pass Threshold: 70 points
    # Must have at least: Workspace + Tool + Price + Alert Enabled (10+20+20+25 = 75)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }