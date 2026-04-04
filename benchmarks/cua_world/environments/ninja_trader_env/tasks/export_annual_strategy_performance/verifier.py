#!/usr/bin/env python3
"""
Verifier for export_annual_strategy_performance task.

Verifies that the agent:
1. Created the CSV output file.
2. The file contains Annual breakdown (2023, 2024 data rows) instead of just summary.
3. Used the VLM to verify the workflow steps (Strategy Analyzer usage).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_annual_strategy_performance(traj, env_info, task_info):
    """
    Verify export_annual_strategy_performance task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # CRITERION 1: File Existence & Creation (20 pts)
    # ---------------------------------------------------------
    output_exists = result.get('output_exists', False)
    created_fresh = result.get('file_created_during_task', False)
    
    if output_exists:
        if created_fresh:
            score += 20
            feedback_parts.append("File 'annual_report.csv' created successfully (+20)")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp indicates it wasn't created during this task (+5)")
    else:
        feedback_parts.append("Output file 'annual_report.csv' not found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # CRITERION 2: Content Verification - Annual Breakdown (40 pts)
    # ---------------------------------------------------------
    has_2023 = result.get('content_has_2023', False)
    has_2024 = result.get('content_has_2024', False)
    has_metrics = result.get('content_has_net_profit', False)
    
    if has_2023 and has_2024:
        score += 40
        feedback_parts.append("Annual breakdown verified (found 2023/2024 rows) (+40)")
    elif has_2023 or has_2024:
        score += 20
        feedback_parts.append("Partial annual data found (only one year visible) (+20)")
    else:
        feedback_parts.append("No annual breakdown found. Did you switch View to 'Annual'? (0)")

    # ---------------------------------------------------------
    # CRITERION 3: Content Verification - Valid Data (10 pts)
    # ---------------------------------------------------------
    if has_metrics:
        score += 10
        feedback_parts.append("Performance metrics (Net Profit) found in CSV (+10)")
    else:
        feedback_parts.append("CSV appears empty or malformed (no headers found) (0)")

    # ---------------------------------------------------------
    # CRITERION 4: VLM Workflow Verification (30 pts)
    # ---------------------------------------------------------
    # We want to confirm the agent actually used Strategy Analyzer
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + ([final_frame] if final_frame else [])
    
    vlm_prompt = """
    Analyze these screenshots of a NinjaTrader trading task.
    The user is supposed to:
    1. Open the 'Strategy Analyzer'.
    2. Run a backtest on SPY.
    3. Change the display period to 'Annual'.
    4. Export the results.
    
    Look for:
    - A window titled 'Strategy Analyzer'.
    - A dropdown or grid view showing years like '2023', '2024' (indicating Annual view).
    - An 'Export' context menu or save dialog.
    
    Answer JSON:
    {
        "strategy_analyzer_seen": true/false,
        "annual_view_seen": true/false,
        "export_action_seen": true/false
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=all_images, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('strategy_analyzer_seen'):
            vlm_score += 10
        if parsed.get('annual_view_seen'):
            vlm_score += 10
        if parsed.get('export_action_seen'):
            vlm_score += 10
            
        score += vlm_score
        feedback_parts.append(f"VLM verified workflow steps ({vlm_score}/30)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if file is perfect, give partial VLM credit
        if score >= 70:
            score += 15
            feedback_parts.append("VLM skipped, granted partial credit based on file success (+15)")

    # Final Check
    passed = score >= 70 and has_2023 and has_2024
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }