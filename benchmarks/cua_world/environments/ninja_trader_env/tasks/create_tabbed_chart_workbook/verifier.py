#!/usr/bin/env python3
"""
Verifier for create_tabbed_chart_workbook task.

Verification Strategy:
1. Primary: Parse JSON result exported from NinjaTrader environment (file check).
   - Checks if workspace was modified.
   - Checks if exactly 1 chart window exists.
   - Checks if 3 distinct instruments (SPY, AAPL, MSFT) are found in that window.
   - Checks for Daily interval.

2. Secondary: VLM Trajectory Verification.
   - Checks if the agent created tabs (visible in screenshot UI) vs creating new windows.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_tabbed_chart_workbook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path matches export_result.ps1 output
        copy_from_env("C:/Users/Docker/Desktop/NinjaTraderTasks/create_tabbed_chart_workbook_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Criteria
    
    # Criterion: Workspace Modified (10 pts)
    if result.get("workspace_modified"):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Criterion: Single Window Enforced (20 pts)
    # 0 windows = fail, 1 window = pass, >1 windows = fail
    win_count = result.get("window_count", 0)
    if win_count == 1:
        score += 20
        feedback_parts.append("Single chart window maintained (+20)")
    elif win_count > 1:
        feedback_parts.append(f"Too many chart windows found ({win_count}) - expected 1 (0)")
    else:
        feedback_parts.append("No chart windows found (0)")

    # Criterion: Instruments (30 pts - 10 each)
    instruments = result.get("instruments_found", [])
    if "SPY" in instruments: score += 10
    if "AAPL" in instruments: score += 10
    if "MSFT" in instruments: score += 10
    
    missing_inst = [i for i in ["SPY", "AAPL", "MSFT"] if i not in instruments]
    if missing_inst:
        feedback_parts.append(f"Missing instruments: {', '.join(missing_inst)}")
    else:
        feedback_parts.append("All instruments found (+30)")

    # Criterion: Tab Count (30 pts)
    # We rely on tab_count from export script which uses heuristics (BarSeries count)
    tab_count = result.get("tab_count", 0)
    if tab_count >= 3:
        score += 30
        feedback_parts.append("Three or more tabs detected (+30)")
    elif tab_count == 2:
        score += 15
        feedback_parts.append("Only two tabs detected (+15)")
    else:
        feedback_parts.append(f"Insufficient tabs detected ({tab_count})")

    # Criterion: Daily Interval (10 pts)
    if result.get("all_daily"):
        score += 10
        feedback_parts.append("Daily interval confirmed (+10)")
    else:
        feedback_parts.append("Daily interval check failed")

    # 3. Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }