#!/usr/bin/env python3
"""
Verifier for configure_market_analyzer_heatmap task.

SCORING CRITERIA:
1. Workspace "HeatmapTask" exists and modified (10 pts)
2. Correct Instruments (SPY, AAPL, MSFT) (15 pts)
3. Sorting: NetChangePercent Descending (25 pts)
4. Condition: Positive > 0 is Green (25 pts)
5. Condition: Negative < 0 is Red (25 pts)

Total: 100 pts
Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Valid color codes (approximate hex for standard NinjaTrader brushes)
# Greenish
GREEN_HEXES = ['#FF008000', '#FF00FF00', '#FF90EE90', '#FF32CD32', '#FF2E8B57'] # Green, Lime, LightGreen, LimeGreen, SeaGreen
# Reddish
RED_HEXES = ['#FFFF0000', '#FFFFC0CB', '#FFFFB6C1', '#FF8B0000', '#FFDC143C']   # Red, Pink, LightPink, DarkRed, Crimson

def verify_configure_market_analyzer_heatmap(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define result path inside container
    result_path = "C:\\Users\\Docker\\Desktop\\configure_market_analyzer_heatmap_result.json"
    
    # Copy result to local temp
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse result file. Ensure workspace was saved as 'HeatmapTask'. Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Existence & Modification (10 pts)
    if result.get("workspace_exists", False):
        if result.get("file_modified_during_task", False):
            score += 10
            feedback.append("Workspace 'HeatmapTask' saved successfully (+10).")
        else:
            feedback.append("Workspace exists but was NOT modified during this task session.")
    else:
        feedback.append("Workspace 'HeatmapTask' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Instruments (15 pts)
    found_instruments = result.get("instruments", [])
    required = ["SPY", "AAPL", "MSFT"]
    missing = [i for i in required if i not in found_instruments]
    
    if not missing:
        score += 15
        feedback.append("All instruments (SPY, AAPL, MSFT) found (+15).")
    else:
        # Partial credit? No, robust check requires all 3.
        feedback.append(f"Missing instruments: {missing}.")

    # 3. Sorting (25 pts)
    # Check column name (NetChangePercent) and Direction (Descending)
    sort_col = result.get("sort_column", "")
    sort_dir = result.get("sort_direction", "")
    
    if "NetChangePercent" in sort_col and "Descending" in sort_dir:
        score += 25
        feedback.append("Sorting correctly set to Net Change % Descending (+25).")
    elif "NetChangePercent" in sort_col:
        score += 10
        feedback.append("Sorted by correct column but wrong direction (+10).")
    else:
        feedback.append(f"Incorrect sorting: Column='{sort_col}', Direction='{sort_dir}'.")

    # 4 & 5. Conditions (50 pts total)
    conditions = result.get("conditions", [])
    
    # We look for logic: (Type: Greater, Value: 0, Color: Greenish) AND (Type: Less, Value: 0, Color: Reddish)
    has_positive_cond = False
    has_negative_cond = False
    
    for cond in conditions:
        ctype = cond.get("type", "")
        cval = str(cond.get("value", ""))
        chex = cond.get("color_hex", "").upper()
        
        # Check Positive
        if "Greater" in ctype and cval == "0":
            # Check color - allow generous matching or specific hexes
            # Also allow if hex is empty (maybe user picked custom) but let's be strict on hex presence for automation
            # Note: NinjaTrader often saves hex with alpha, e.g., #FF00FF00
            if any(gh in chex for gh in GREEN_HEXES):
                has_positive_cond = True
        
        # Check Negative
        if "Less" in ctype and cval == "0":
            if any(rh in chex for rh in RED_HEXES):
                has_negative_cond = True

    if has_positive_cond:
        score += 25
        feedback.append("Positive condition (Green > 0) verified (+25).")
    else:
        feedback.append("Positive condition (Green > 0) missing or incorrect color.")

    if has_negative_cond:
        score += 25
        feedback.append("Negative condition (Red < 0) verified (+25).")
    else:
        feedback.append("Negative condition (Red < 0) missing or incorrect color.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }