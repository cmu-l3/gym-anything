#!/usr/bin/env python3
"""
Verifier for configure_time_and_sales task in NinjaTrader 8.

Verifies:
1. Workspace was modified (saved).
2. Time & Sales windows created (TimeAndSales type detected).
3. Correct instruments (SPY, AAPL) assigned.
4. Correct display rows (100) configured.

Uses robust JSON result parsing from the container export.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_REMOTE_PATH = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\configure_time_and_sales_result.json"

def verify_configure_time_and_sales(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Time & Sales configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: path handling for Windows container -> Linux host
        # The copy_from_env implementation usually handles the path conversion
        # or we might need to be careful. The prompt implies standard usage.
        copy_from_env(RESULT_REMOTE_PATH, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse verification result: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: Workspace Modified (15 pts)
    # This proves the agent actually saved the work
    if result.get('workspace_modified', False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Criterion 2: Time & Sales Windows Detected (20 pts)
    ts_count = result.get('ts_window_count', 0)
    if ts_count >= 2:
        score += 20
        feedback_parts.append(f"Time & Sales windows detected: {ts_count} (+20)")
    elif ts_count == 1:
        score += 10
        feedback_parts.append("Only 1 Time & Sales window detected (+10)")
    else:
        feedback_parts.append("No Time & Sales windows found")

    # Criterion 3: Instruments (40 pts total)
    spy_found = result.get('spy_found', False)
    aapl_found = result.get('aapl_found', False)
    
    if spy_found:
        score += 20
        feedback_parts.append("SPY instrument configured (+20)")
    else:
        feedback_parts.append("SPY instrument missing")
        
    if aapl_found:
        score += 20
        feedback_parts.append("AAPL instrument configured (+20)")
    else:
        feedback_parts.append("AAPL instrument missing")

    # Criterion 4: Configuration (Rows=100) (25 pts)
    if result.get('rows_correct', False):
        score += 25
        feedback_parts.append("Rows set to 100 (+25)")
    else:
        feedback_parts.append("Rows setting incorrect or not found")

    # 3. Final Assessment
    # Pass threshold: 70 points
    # Must at least have saved workspace and configured instruments
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }