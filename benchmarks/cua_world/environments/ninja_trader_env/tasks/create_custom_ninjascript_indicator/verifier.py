#!/usr/bin/env python3
"""
Verifier for create_custom_ninjascript_indicator task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_ninjascript_indicator(traj, env_info, task_info):
    """
    Verify the agent created, compiled, and applied a custom ATRP indicator.
    
    Scoring Breakdown (100 pts):
    - 15 pts: Source file exists
    - 35 pts: Code logic correct (ATR, Close, 100, Period)
    - 15 pts: Compilation successful (DLL updated)
    - 20 pts: Workspace saved with SPY and Indicator
    - 15 pts: VLM Verification (Visual confirmation of chart/editor)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Path must match what is in export_result.ps1
        # If env is Windows, path is C:\Users\Docker\Desktop\task_result.json
        # copy_from_env should handle the absolute path mapping if configured correctly,
        # otherwise we might need to adjust based on how the gym maps paths.
        # Assuming the standard path provided in metadata works.
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Source File Check (15 pts)
    if result.get('source_file_found'):
        score += 15
        feedback.append("Source file created.")
    else:
        feedback.append("No custom indicator source file found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Code Logic Check (35 pts)
    checks = result.get('code_checks', {})
    code_score = 0
    if checks.get('has_atr'): code_score += 10
    if checks.get('has_close'): code_score += 10
    if checks.get('has_100'): code_score += 5
    if checks.get('has_period'): code_score += 10
    
    score += code_score
    feedback.append(f"Code logic score: {code_score}/35")

    # 3. Compilation Check (15 pts)
    if result.get('compilation_success'):
        score += 15
        feedback.append("Compilation successful (DLL updated).")
    else:
        feedback.append("Compilation failed or not detected.")

    # 4. Workspace Check (20 pts)
    ws_checks = result.get('workspace_checks', {})
    if result.get('workspace_modified'):
        ws_score = 0
        if ws_checks.get('has_spy'): ws_score += 10
        if ws_checks.get('has_atrp_on_chart'): ws_score += 10
        score += ws_score
        feedback.append(f"Workspace score: {ws_score}/20")
    else:
        feedback.append("Workspace not saved.")

    # 5. VLM Verification (15 pts)
    # Check for visual evidence of Chart or Editor
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots from NinjaTrader 8.
    I am looking for evidence that the user:
    1. Opened the NinjaScript Editor (code visible).
    2. Opened a Chart window.
    3. Applied an indicator that looks like a line plot in a panel below the price.
    
    Does the final screenshot show a chart with a sub-panel indicator?
    Respond JSON: {"editor_seen": bool, "chart_seen": bool, "indicator_panel_seen": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('chart_seen'): vlm_score += 5
        if parsed.get('indicator_panel_seen'): vlm_score += 10
        # Bonus for editor seen, but not strictly required for final output score
        
        score += vlm_score
        feedback.append(f"Visual verification score: {vlm_score}/15")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback.append("VLM check skipped due to error.")
        # Grant partial points if programmatic checks passed strongly
        if score > 60:
            score += 10

    passed = score >= 60 and result.get('source_file_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }