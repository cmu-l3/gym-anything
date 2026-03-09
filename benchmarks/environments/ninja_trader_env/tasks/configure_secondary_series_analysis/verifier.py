#!/usr/bin/env python3
"""
Verifier for configure_secondary_series_analysis task.

Task:
1. Create AAPL Daily chart (Primary)
2. Add MSFT Daily (Secondary)
3. Add EMA(20) applied to MSFT

Scoring (100 points):
- Workspace modified (10 pts)
- Chart with multiple instruments found (30 pts)
- EMA indicator found (15 pts)
- EMA applied to Secondary Series (Index 1) (35 pts)
- EMA Period = 20 (10 pts)

Pass Threshold: 80 points (Must get the Series Index correct)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_secondary_series_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = "C:/Users/Docker/Desktop/task_result.json"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}. Agent may not have saved the workspace."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Modified (10 pts)
    if result.get("workspace_saved", False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        return {"passed": False, "score": 0, "feedback": "Workspace not saved. Task requires saving workspace."}

    # 2. Chart with Primary (AAPL) and Secondary (MSFT) (30 pts)
    # Check if both instruments were detected in the XML
    has_aapl = result.get("has_primary_aapl", False)
    has_msft = result.get("has_secondary_msft", False)
    chart_found = result.get("chart_found", False) # Based on instrument count >= 2
    
    if has_aapl and has_msft:
        score += 30
        feedback_parts.append("Both AAPL and MSFT series found (+30)")
    elif has_aapl or has_msft:
        score += 10
        feedback_parts.append("Only one instrument found (+10)")
    else:
        feedback_parts.append("No correct instruments found (0)")

    # 3. EMA Indicator Found (15 pts)
    if result.get("has_ema", False):
        score += 15
        feedback_parts.append("EMA indicator present (+15)")
    else:
        feedback_parts.append("EMA indicator missing (0)")

    # 4. EMA Applied to Secondary Series (35 pts) - CRITICAL
    # Input series index should be 1 (Secondary) or higher, definitely not 0 (Primary/Default)
    idx = result.get("ema_input_series_index", -1)
    if idx >= 1:
        score += 35
        feedback_parts.append(f"EMA correctly applied to Secondary Series (Index {idx}) (+35)")
    elif idx == 0:
        feedback_parts.append("EMA applied to Primary Series (Index 0) - WRONG TARGET (0)")
    else:
        feedback_parts.append("Could not determine EMA input series (0)")

    # 5. EMA Period Correct (10 pts)
    period = result.get("ema_period", 0)
    if period == 20:
        score += 10
        feedback_parts.append("EMA Period 20 correct (+10)")
    else:
        feedback_parts.append(f"EMA Period incorrect: {period} (0)")

    # Determine Pass/Fail
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }