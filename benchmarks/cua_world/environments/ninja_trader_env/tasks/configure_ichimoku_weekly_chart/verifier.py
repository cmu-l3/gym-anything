#!/usr/bin/env python3
"""
Verifier for configure_ichimoku_weekly_chart task.

Verifies:
1. Workspace file was created/modified after task start.
2. SPY instrument is present in the workspace.
3. Chart is set to Weekly timeframe.
4. Ichimoku Cloud indicator is present with correct parameters (9, 26, 52).
5. ADX indicator is present with correct parameter (14).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ichimoku_weekly_chart(traj, env_info, task_info):
    """
    Verify the configuration of the Ichimoku Weekly chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = r"C:\Users\Docker\Desktop\NinjaTraderTasks\task_result.json"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task result (workspace likely not saved or script failed)."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Score calculation
    score = 0
    feedback_parts = []
    
    # 1. Activity Check (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace modified (+10)")
    else:
        feedback_parts.append("No workspace changes detected")
        return {"passed": False, "score": 0, "feedback": "No workspace changes detected (did you save?)"}

    # 2. Instrument Check (15 pts)
    if result.get('spy_found', False):
        score += 15
        feedback_parts.append("SPY found (+15)")
    else:
        feedback_parts.append("SPY instrument not found")

    # 3. Timeframe Check (20 pts)
    if result.get('weekly_found', False):
        score += 20
        feedback_parts.append("Weekly timeframe correct (+20)")
    else:
        feedback_parts.append("Weekly timeframe not set")

    # 4. Ichimoku Check (35 pts total)
    if result.get('ichimoku_found', False):
        score += 20
        feedback_parts.append("Ichimoku indicator added (+20)")
        
        if result.get('ichimoku_params_correct', False):
            score += 15
            feedback_parts.append("Ichimoku params correct (+15)")
        else:
            feedback_parts.append("Ichimoku params incorrect (expected 9/26/52)")
    else:
        feedback_parts.append("Ichimoku indicator missing")

    # 5. ADX Check (20 pts total)
    if result.get('adx_found', False):
        score += 15
        feedback_parts.append("ADX indicator added (+15)")
        
        if result.get('adx_period_correct', False):
            score += 5
            feedback_parts.append("ADX period correct (+5)")
        else:
            feedback_parts.append("ADX period incorrect (expected 14)")
    else:
        feedback_parts.append("ADX indicator missing")

    # Determine Success
    # Threshold: 70 points.
    # Must at least have SPY + Ichimoku to pass reasonably.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }