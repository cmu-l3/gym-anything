#!/usr/bin/env python3
"""
Verifier for run_backtest_with_custom_execution_settings task.

Checks:
1. Workspace modified (20 pts)
2. Strategy & Instrument correct (20 pts)
3. Order Quantity == 500 (30 pts)
4. Slippage == 2 (30 pts)

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_run_backtest_with_custom_execution_settings(traj, env_info, task_info):
    """
    Verify the agent configured backtest settings correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: The export script saves to C:\tmp\task_result.json which maps to standard path structure
    # However, copy_from_env usually handles container paths. 
    # For Windows containers, paths might need careful handling or the framework abstracts it.
    # We assume "/tmp/task_result.json" or similar alias, or full windows path if supported.
    # Given the previous examples for this env, we try the known export path.
    # If the environment maps C:\tmp to /tmp, we use /tmp. 
    # Standard practice here is to try the explicit path created by export script.
    
    # NOTE: Windows paths in copy_from_env might require forward slashes
    result_path_in_container = "C:/tmp/task_result.json"

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path_in_container, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        # Fallback: try Linux-style path just in case of volume mapping
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Workspace Modification (20 pts)
    if result.get('workspace_modified', False):
        score += 20
        feedback.append("Workspace saved (+20)")
    else:
        feedback.append("Workspace NOT saved (0)")
        # Early exit if nothing saved? No, check other fields just in case regex worked on old file (unlikely due to time check)
        
    # 2. Strategy & Instrument (20 pts)
    strat = result.get('strategy_found', False)
    inst = result.get('instrument_correct', False)
    
    if strat and inst:
        score += 20
        feedback.append("Strategy and Instrument correct (+20)")
    elif strat or inst:
        score += 10
        feedback.append("Partial Strategy/Instrument match (+10)")
    else:
        feedback.append("Wrong Strategy or Instrument (0)")

    # 3. Quantity (30 pts)
    qty = result.get('found_quantity', -1)
    if qty == 500:
        score += 30
        feedback.append("Order Quantity 500 correct (+30)")
    else:
        feedback.append(f"Order Quantity incorrect (Found: {qty}, Expected: 500) (0)")

    # 4. Slippage (30 pts)
    slip = result.get('found_slippage', -1)
    if slip == 2:
        score += 30
        feedback.append("Slippage 2 ticks correct (+30)")
    else:
        feedback.append(f"Slippage incorrect (Found: {slip}, Expected: 2) (0)")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }