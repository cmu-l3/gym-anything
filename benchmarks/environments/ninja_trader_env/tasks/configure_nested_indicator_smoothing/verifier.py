#!/usr/bin/env python3
"""
Verifier for Configure Nested Indicator Smoothing task.

Verifies:
1. Workspace was modified/saved.
2. SPY chart exists.
3. RSI indicator exists.
4. SMA indicator exists.
5. SMA is configured to use RSI as input (inferred via Panel alignment).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_nested_indicator_smoothing(traj, env_info, task_info):
    """
    Verify the nested indicator configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_path = r"C:\Users\Docker\Desktop\NinjaTraderTasks\result.json"
    
    # Temp file for extraction
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - task likely not attempted"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Saved (20 pts)
    if result.get("workspace_saved", False):
        score += 20
        feedback_parts.append("Workspace saved (+20)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # 2. Chart/Instrument (10 pts)
    if result.get("chart_found", False) and result.get("instrument_correct", False):
        score += 10
        feedback_parts.append("SPY Chart found (+10)")
    else:
        feedback_parts.append("SPY Chart not found (0)")

    # 3. RSI Present (15 pts)
    if result.get("rsi_found", False):
        score += 15
        feedback_parts.append("RSI Indicator found (+15)")
    else:
        feedback_parts.append("RSI not found (0)")

    # 4. SMA Present (15 pts)
    if result.get("sma_found", False):
        score += 15
        feedback_parts.append("SMA Indicator found (+15)")
    else:
        feedback_parts.append("SMA not found (0)")

    # 5. Nested Configuration (40 pts)
    # The crucial step: SMA must be on the same panel as RSI (indicating it's applied to it)
    if result.get("nested_correct", False):
        score += 40
        feedback_parts.append("SMA is correctly nested on RSI panel (+40)")
    else:
        feedback_parts.append("SMA is NOT correctly nested on RSI panel (0)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }