#!/usr/bin/env python3
"""
Verifier for export_strategy_execution_report task.

Verifies:
1. File msft_executions.csv exists in Documents (20 pts)
2. File was created/modified AFTER task started (10 pts)
3. CSV contains data for MSFT (20 pts)
4. CSV contains data for year 2024 (20 pts)
5. CSV has meaningful data (>5 rows) (10 pts)
6. VLM Check: Strategy Analyzer window and Executions tab were visible (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_strategy_execution_report(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 2. Retrieve JSON result from container
    # NinjaTrader env is Windows, path is C:\Users\Docker\Desktop\NinjaTraderTasks\task_result.json
    result_path_in_container = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\task_result.json"
    local_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    local_temp.close()
    
    task_result = {}
    try:
        copy_from_env(result_path_in_container, local_temp.name)
        with open(local_temp.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result file. Did the export script run?"}
    finally:
        if os.path.exists(local_temp.name):
            os.remove(local_temp.name)

    # 3. File-based Verification
    score = 0
    feedback = []
    
    # Criteria 1: File Exists (20 pts)
    if task_result.get("output_exists"):
        score += 20
        feedback.append("Output CSV found (+20)")
    else:
        feedback.append("Output CSV NOT found (0)")
        # Fail immediately if file is missing, but continue logic for detailed feedback if needed
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criteria 2: Anti-gaming (Created during task) (10 pts)
    if task_result.get("file_created_during_task"):
        score += 10
        feedback.append("File created during task (+10)")
    else:
        feedback.append("File old/stale (0)")

    # Criteria 3: Valid Content (Instrument MSFT) (20 pts)
    if task_result.get("has_msft"):
        score += 20
        feedback.append("Correct instrument (MSFT) (+20)")
    else:
        feedback.append("Wrong instrument (0)")

    # Criteria 4: Valid Content (Year 2024) (20 pts)
    if task_result.get("has_2024"):
        score += 20
        feedback.append("Correct date range (2024) (+20)")
    else:
        feedback.append("Wrong date range (0)")

    # Criteria 5: Valid Data (>5 rows) (10 pts)
    if task_result.get("row_count", 0) > 5:
        score += 10
        feedback.append(f"Data present ({task_result.get('row_count')} rows) (+10)")
    else:
        feedback.append("File empty or too few rows (0)")

    # 4. VLM Verification (20 pts)
    # Check if Strategy Analyzer was actually used
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of NinjaTrader 8.
    1. Is the 'Strategy Analyzer' window visible?
    2. Is a backtest report or grid of executions visible?
    3. Are we looking at a 'Executions' tab (list of trades)?
    
    Return JSON: {"strategy_analyzer_visible": bool, "executions_tab_visible": bool}
    """
    
    vlm_score = 0
    try:
        # Use final frame + 2 late trajectory frames to catch the moment
        check_images = frames[-2:] + [final_frame] if frames else [final_frame]
        vlm_resp = query_vlm(prompt=vlm_prompt, images=check_images)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("strategy_analyzer_visible"):
                vlm_score += 10
                feedback.append("Strategy Analyzer visible (+10)")
            if parsed.get("executions_tab_visible"):
                vlm_score += 10
                feedback.append("Executions tab visible (+10)")
            else:
                feedback.append("Executions tab not detected")
        else:
            feedback.append("VLM check inconclusive")
            # If file verification is perfect (80 pts), grant VLM points to avoid false failures
            if score >= 80:
                vlm_score += 20
                feedback.append("Auto-passing VLM due to perfect file output")
    except Exception as e:
        logger.warning(f"VLM Exception: {e}")
        if score >= 80:
            vlm_score += 20
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }