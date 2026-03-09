#!/usr/bin/env python3
"""
Verifier for create_trend_monitor_dashboard task.

Verification Logic:
1. Workspace must be modified (anti-gaming).
2. Market Analyzer window must exist.
3. Target instruments (SPY, AAPL, MSFT) must be present.
4. "Last" column must be present.
5. Conditional logic must be configured:
   - Uses SimpleMovingAverage (SMA)
   - Uses Period 50
   - Assigns appropriate colors (Green/Red families)

Scoring:
- Workspace Modified: 10 pts
- MA Window & Data: 15 pts
- Conditions Exist: 20 pts
- Logic Correct (SMA present): 25 pts
- Period Correct (50): 15 pts
- Colors Configured: 15 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_trend_monitor_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Path inside the container (Windows path mapped to Linux format for copy if needed, 
    # but copy_from_env usually handles the internal path string provided by export script)
    # The export script saves to C:\tmp\task_result.json. 
    # In 'ninja_trader_env', this often maps to a path accessible via the agent user.
    # We will try the standard path.
    remote_path = "C:\\tmp\\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Verification (10 pts)
    if result.get("workspace_found", False) and result.get("workspace_modified", False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace not saved or not modified")

    # 2. Window & Data (15 pts)
    if result.get("has_market_analyzer", False):
        instruments = result.get("instruments_found", [])
        inst_count = len(instruments)
        if inst_count >= 3:
            score += 15
            feedback_parts.append(f"Market Analyzer found with {inst_count} instruments (+15)")
        elif inst_count > 0:
            score += 10
            feedback_parts.append(f"Market Analyzer found with {inst_count}/3 instruments (+10)")
        else:
            score += 5
            feedback_parts.append("Market Analyzer found but no target instruments (+5)")
    else:
        feedback_parts.append("No Market Analyzer window found")

    # 3. Column & Conditions (20 pts)
    if result.get("has_last_column", False):
        if result.get("has_conditions", False):
            score += 20
            feedback_parts.append("Conditions configured on Last column (+20)")
        else:
            score += 5
            feedback_parts.append("Last column found but no conditions (+5)")
    else:
        feedback_parts.append("Last column not found")

    # 4. SMA Logic (25 pts)
    if result.get("has_sma_condition", False):
        score += 25
        feedback_parts.append("SMA indicator used in conditions (+25)")
    else:
        feedback_parts.append("SMA indicator NOT detected in conditions")

    # 5. SMA Period (15 pts)
    if result.get("sma_period_correct", False):
        score += 15
        feedback_parts.append("SMA Period set to 50 (+15)")
    elif result.get("has_sma_condition", False):
        feedback_parts.append("SMA used but Period 50 not detected")

    # 6. Visual Colors (15 pts)
    color_score = 0
    if result.get("has_bullish_color", False):
        color_score += 8
    if result.get("has_bearish_color", False):
        color_score += 7
    
    if color_score > 0:
        score += color_score
        feedback_parts.append(f"Colors configured ({color_score}/15 pts)")
    
    # Threshold check
    # Minimum required: Workspace saved, MA exists, Conditions using SMA exist
    # 10 + 5 (MA) + 20 (Conditions) + 25 (SMA) = 60 points minimum for a 'pass' 
    # if we are strict about the core logic.
    passed = score >= 65 and result.get("has_sma_condition", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }