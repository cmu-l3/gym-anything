#!/usr/bin/env python3
"""
Verifier for develop_and_backtest_ema_strategy task.
"""

import json
import re
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_develop_and_backtest_ema_strategy(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the SampleEMACrossover.cs file.
    2. Refactored the code to use EMA instead of SMA.
    3. Configured/Ran a backtest in the Strategy Analyzer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    windows_data = result.get("windows_data", {})
    source_code = windows_data.get("source_code", "")
    
    score = 0
    feedback_parts = []

    # Criterion 1: Strategy File Exists (20 pts)
    if windows_data.get("strategy_exists"):
        score += 20
        feedback_parts.append("Strategy file created (+20)")
    else:
        feedback_parts.append("Strategy file missing (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Logic Refactored to EMA (30 pts)
    # Check for class name
    if "class SampleEMACrossover" in source_code:
        score += 5
        feedback_parts.append("Class renamed correctly (+5)")
    else:
        feedback_parts.append("Class name incorrect (0)")

    # Check for EMA usage
    ema_matches = re.findall(r'\bEMA\b|\bExponentialMovingAverage\b', source_code)
    if len(ema_matches) >= 2: # At least declaration and instantiation
        score += 25
        feedback_parts.append("EMA logic detected (+25)")
    else:
        feedback_parts.append("EMA logic missing or insufficient (0)")

    # Criterion 3: Old Logic Removed (10 pts)
    # Check if active code still uses SMA
    # Simple check: remove comments then check for SMA
    code_no_comments = re.sub(r'//.*', '', source_code) # Single line
    code_no_comments = re.sub(r'/\*.*?\*/', '', code_no_comments, flags=re.DOTALL) # Multi line
    
    sma_matches = re.findall(r'\bSMA\b|\bSimpleMovingAverage\b', code_no_comments)
    # We allow "SampleMACrossover" string if it appears in comments or legacy properties, 
    # but the logic `SMA(...)` should be gone.
    # Stricter check: Look for `SMA(` or `SimpleMovingAverage(`
    active_sma_calls = re.findall(r'(\bSMA\b|\bSimpleMovingAverage\b)\s*\(', code_no_comments)
    
    if len(active_sma_calls) == 0:
        score += 10
        feedback_parts.append("SMA logic removed (+10)")
    else:
        feedback_parts.append(f"Found {len(active_sma_calls)} remaining SMA calls (0)")

    # Criterion 4: Backtest Configured (20 pts)
    if windows_data.get("backtest_configured"):
        score += 20
        feedback_parts.append("Backtest configuration found in workspace (+20)")
    else:
        feedback_parts.append("Backtest not found in workspace (0)")

    # Criterion 5: Workspace/Backtest Execution Evidence (20 pts)
    # We use workspace_saved as a proxy for completed workflow here, 
    # ideally we would check for a backtest report file, but workspace persistence is the minimal requirement
    if windows_data.get("workspace_saved") and windows_data.get("backtest_configured"):
        score += 20
        feedback_parts.append("Workspace saved with backtest (+20)")
    elif windows_data.get("workspace_saved"):
        score += 10
        feedback_parts.append("Workspace saved but backtest missing (+10)")
    else:
        feedback_parts.append("Workspace not saved (0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }